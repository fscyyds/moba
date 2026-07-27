// MOBA 3v3 PC 客户端
// WASD + 鼠标右键移动，鼠标左键普攻，Q/W/E/R 朝鼠标释放技能

const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');
const minimapCanvas = document.getElementById('minimap');
const minimapCtx = minimapCanvas.getContext('2d');
const menuEl = document.getElementById('menu');
const hudEl = document.getElementById('hud');
const gameoverEl = document.getElementById('gameover');
const connectionEl = document.getElementById('connection');

let ws = null;
let myTeam = null;
let myHeroId = null;
let gameState = null;
let selectedRole = null;
let scale = 1;
let cameraX = 3000, cameraY = 2000;
let mouseX = 0, mouseY = 0;

function getMyHero() {
    return gameState ? gameState.heroes.find(h => h.id === myHeroId) : null;
}
const keys = {};

const MAP_W = 10000, MAP_H = 10000;

// 瓦片地图数据
let mapData = null;
fetch('/map.json')
    .then(r => r.json())
    .then(data => { mapData = data; })
    .catch(err => console.error('加载地图失败', err));

// 打击感反馈：飘字、震动、顿帧
const damageNumbers = [];
let shakeTimer = 0;
let shakeIntensity = 0;
let hitStopTimer = 0;
let pendingState = null;

function triggerHitStop(duration) {
    hitStopTimer = duration || 0.06;
}

// ==================== Web Audio 音效引擎 ====================
// 使用浏览器内置 Web Audio API 合成音效，无需外部音频资源
const AudioEngine = {
    ctx: null,
    masterGain: null,
    bgmGain: null,
    sfxGain: null,
    muted: false,
    bgmNodes: [],
    initialized: false,

    init() {
        if (this.initialized) return true;
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        if (!AudioContext) return false;
        this.ctx = new AudioContext();

        this.masterGain = this.ctx.createGain();
        this.masterGain.gain.value = 0.5;
        this.masterGain.connect(this.ctx.destination);

        this.bgmGain = this.ctx.createGain();
        this.bgmGain.gain.value = 0.08;
        this.bgmGain.connect(this.masterGain);

        this.sfxGain = this.ctx.createGain();
        this.sfxGain.gain.value = 0.55;
        this.sfxGain.connect(this.masterGain);

        this.initialized = true;
        return true;
    },

    resume() {
        if (this.ctx && this.ctx.state === 'suspended') this.ctx.resume();
    },

    setMuted(m) {
        this.muted = m;
        if (this.masterGain) this.masterGain.gain.value = m ? 0 : 0.5;
        updateMuteButton();
    },

    toggleMute() {
        this.setMuted(!this.muted);
    },

    volumeForDistance(x, y) {
        const me = getMyHero();
        if (!me || me.dead) return 1;
        const d = Math.hypot(me.x - x, me.y - y);
        const maxD = 1600;
        return Math.max(0.12, 1 - d / maxD);
    },

    _noiseBuffer(duration) {
        const samples = Math.ceil(this.ctx.sampleRate * duration);
        const buffer = this.ctx.createBuffer(1, samples, this.ctx.sampleRate);
        const data = buffer.getChannelData(0);
        for (let i = 0; i < samples; i++) data[i] = Math.random() * 2 - 1;
        return buffer;
    },

    _scheduleStop(nodes, when) {
        for (const n of nodes) {
            if (n && typeof n.stop === 'function') try { n.stop(when); } catch (e) {}
        }
    },

    playHit(x, y) {
        if (this.muted || !this.ctx) return;
        const t = this.ctx.currentTime;
        const vol = this.volumeForDistance(x, y);

        // 短促低频冲击
        const gain = this.ctx.createGain();
        gain.connect(this.sfxGain);
        gain.gain.setValueAtTime(0.35 * vol, t);
        gain.gain.exponentialRampToValueAtTime(0.01, t + 0.08);

        const osc = this.ctx.createOscillator();
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(360, t);
        osc.frequency.exponentialRampToValueAtTime(90, t + 0.08);
        osc.connect(gain);
        osc.start(t);
        osc.stop(t + 0.09);

        // 短噪音增加“肉感”
        const noise = this.ctx.createBufferSource();
        noise.buffer = this._noiseBuffer(0.06);
        const nGain = this.ctx.createGain();
        nGain.connect(this.sfxGain);
        nGain.gain.setValueAtTime(0.2 * vol, t);
        nGain.gain.exponentialRampToValueAtTime(0.01, t + 0.05);
        noise.connect(nGain);
        noise.start(t);
    },

    playSkill(slot, x, y) {
        if (this.muted || !this.ctx) return;
        const t = this.ctx.currentTime;
        const vol = this.volumeForDistance(x, y);

        if (slot === 'q') {
            // 火球：噪声扫频
            const noise = this.ctx.createBufferSource();
            noise.buffer = this._noiseBuffer(0.25);
            const filter = this.ctx.createBiquadFilter();
            filter.type = 'bandpass';
            filter.frequency.setValueAtTime(800, t);
            filter.frequency.exponentialRampToValueAtTime(1200, t + 0.25);
            const gain = this.ctx.createGain();
            gain.connect(this.sfxGain);
            gain.gain.setValueAtTime(0.35 * vol, t);
            gain.gain.exponentialRampToValueAtTime(0.01, t + 0.25);
            noise.connect(filter).connect(gain);
            noise.start(t);
        } else if (slot === 'w') {
            // 魔法爆发：和弦 + 噪声
            const freqs = [330, 392, 523];
            for (const f of freqs) {
                const osc = this.ctx.createOscillator();
                osc.type = 'sine';
                osc.frequency.setValueAtTime(f, t);
                const gain = this.ctx.createGain();
                gain.connect(this.sfxGain);
                gain.gain.setValueAtTime(0.12 * vol, t);
                gain.gain.exponentialRampToValueAtTime(0.01, t + 0.35);
                osc.connect(gain);
                osc.start(t);
                osc.stop(t + 0.36);
            }
        } else if (slot === 'e') {
            // 冲刺：快速下降扫频
            const osc = this.ctx.createOscillator();
            osc.type = 'sawtooth';
            osc.frequency.setValueAtTime(600, t);
            osc.frequency.exponentialRampToValueAtTime(120, t + 0.18);
            const filter = this.ctx.createBiquadFilter();
            filter.type = 'lowpass';
            filter.frequency.setValueAtTime(1500, t);
            filter.frequency.exponentialRampToValueAtTime(300, t + 0.18);
            const gain = this.ctx.createGain();
            gain.connect(this.sfxGain);
            gain.gain.setValueAtTime(0.25 * vol, t);
            gain.gain.exponentialRampToValueAtTime(0.01, t + 0.18);
            osc.connect(filter).connect(gain);
            osc.start(t);
            osc.stop(t + 0.19);
        } else if (slot === 'r') {
            // 大招：低频轰鸣 + 和弦
            const osc = this.ctx.createOscillator();
            osc.type = 'sawtooth';
            osc.frequency.setValueAtTime(120, t);
            osc.frequency.linearRampToValueAtTime(60, t + 0.6);
            const filter = this.ctx.createBiquadFilter();
            filter.type = 'lowpass';
            filter.frequency.setValueAtTime(900, t);
            filter.frequency.exponentialRampToValueAtTime(200, t + 0.6);
            const gain = this.ctx.createGain();
            gain.connect(this.sfxGain);
            gain.gain.setValueAtTime(0.45 * vol, t);
            gain.gain.exponentialRampToValueAtTime(0.01, t + 0.7);
            osc.connect(filter).connect(gain);
            osc.start(t);
            osc.stop(t + 0.75);

            const noise = this.ctx.createBufferSource();
            noise.buffer = this._noiseBuffer(0.7);
            const nGain = this.ctx.createGain();
            nGain.connect(this.sfxGain);
            nGain.gain.setValueAtTime(0.25 * vol, t);
            nGain.gain.exponentialRampToValueAtTime(0.01, t + 0.6);
            noise.connect(filter).connect(nGain);
            noise.start(t);
        }
    },

    playKill(x, y) {
        if (this.muted || !this.ctx) return;
        const t = this.ctx.currentTime;
        const vol = Math.max(0.5, this.volumeForDistance(x, y));
        const freqs = [262, 330, 392, 523, 659];
        for (let i = 0; i < freqs.length; i++) {
            const osc = this.ctx.createOscillator();
            osc.type = 'square';
            osc.frequency.setValueAtTime(freqs[i], t + i * 0.03);
            const gain = this.ctx.createGain();
            gain.connect(this.sfxGain);
            gain.gain.setValueAtTime(0.12 * vol, t + i * 0.03);
            gain.gain.exponentialRampToValueAtTime(0.01, t + 0.45);
            osc.connect(gain);
            osc.start(t + i * 0.03);
            osc.stop(t + 0.5);
        }
    },

    playTowerDestroy(x, y) {
        if (this.muted || !this.ctx) return;
        const t = this.ctx.currentTime;
        const vol = this.volumeForDistance(x, y);

        const noise = this.ctx.createBufferSource();
        noise.buffer = this._noiseBuffer(0.8);
        const filter = this.ctx.createBiquadFilter();
        filter.type = 'lowpass';
        filter.frequency.setValueAtTime(900, t);
        filter.frequency.exponentialRampToValueAtTime(100, t + 0.8);
        const gain = this.ctx.createGain();
        gain.connect(this.sfxGain);
        gain.gain.setValueAtTime(0.55 * vol, t);
        gain.gain.exponentialRampToValueAtTime(0.01, t + 0.9);
        noise.connect(filter).connect(gain);
        noise.start(t);

        const osc = this.ctx.createOscillator();
        osc.type = 'sawtooth';
        osc.frequency.setValueAtTime(80, t);
        osc.frequency.exponentialRampToValueAtTime(30, t + 0.7);
        const oGain = this.ctx.createGain();
        oGain.connect(this.sfxGain);
        oGain.gain.setValueAtTime(0.35 * vol, t);
        oGain.gain.exponentialRampToValueAtTime(0.01, t + 0.7);
        osc.connect(oGain);
        osc.start(t);
        osc.stop(t + 0.75);
    },

    playMonsterKill(type, x, y) {
        if (this.muted || !this.ctx) return;
        const t = this.ctx.currentTime;
        const vol = this.volumeForDistance(x, y);
        if (type === 'baron') {
            // 大龙：低沉号角
            const freqs = [110, 165, 220];
            for (const f of freqs) {
                const osc = this.ctx.createOscillator();
                osc.type = 'sawtooth';
                osc.frequency.setValueAtTime(f, t);
                const gain = this.ctx.createGain();
                gain.connect(this.sfxGain);
                gain.gain.setValueAtTime(0.22 * vol, t);
                gain.gain.exponentialRampToValueAtTime(0.01, t + 1.0);
                osc.connect(gain);
                osc.start(t);
                osc.stop(t + 1.05);
            }
        } else {
            // 小龙：清脆金属
            const freqs = [523, 659, 784, 1047];
            for (let i = 0; i < freqs.length; i++) {
                const osc = this.ctx.createOscillator();
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(freqs[i], t + i * 0.02);
                const gain = this.ctx.createGain();
                gain.connect(this.sfxGain);
                gain.gain.setValueAtTime(0.15 * vol, t + i * 0.02);
                gain.gain.exponentialRampToValueAtTime(0.01, t + 0.5);
                osc.connect(gain);
                osc.start(t + i * 0.02);
                osc.stop(t + 0.55);
            }
        }
    },

    play(soundType, data) {
        switch (soundType) {
            case 'hit': this.playHit(data.x, data.y); break;
            case 'skill': this.playSkill(data.slot, data.x, data.y); break;
            case 'kill': this.playKill(data.x, data.y); break;
            case 'tower_destroy': this.playTowerDestroy(data.x, data.y); break;
            case 'monster_kill': this.playMonsterKill(data.type, data.x, data.y); break;
        }
    },

    startBGM() {
        if (!this.ctx || this.bgmNodes.length) return;
        const t = this.ctx.currentTime;
        // 缓慢变化的氛围底噪，极低音量，不干扰游戏
        const drone1 = this.ctx.createOscillator();
        drone1.type = 'sine';
        drone1.frequency.setValueAtTime(55, t);
        const g1 = this.ctx.createGain();
        g1.gain.value = 0.04;
        drone1.connect(g1).connect(this.bgmGain);
        drone1.start(t);

        const drone2 = this.ctx.createOscillator();
        drone2.type = 'triangle';
        drone2.frequency.setValueAtTime(110, t);
        const g2 = this.ctx.createGain();
        g2.gain.value = 0.02;
        drone2.connect(g2).connect(this.bgmGain);
        drone2.start(t);

        const lfo = this.ctx.createOscillator();
        lfo.frequency.value = 0.1;
        const lfoGain = this.ctx.createGain();
        lfoGain.gain.value = 0.015;
        lfo.connect(lfoGain).connect(g1.gain);
        lfo.start(t);

        this.bgmNodes = [drone1, drone2, lfo];
    },

    stopBGM() {
        for (const n of this.bgmNodes) {
            try { n.stop(); } catch (e) {}
        }
        this.bgmNodes = [];
    }
};

function ensureAudio() {
    if (AudioEngine.init()) {
        AudioEngine.resume();
        AudioEngine.startBGM();
    }
}
window.addEventListener('click', ensureAudio, { once: true });
window.addEventListener('keydown', ensureAudio, { once: true });

function updateMuteButton() {
    const btn = document.getElementById('muteBtn');
    if (btn) btn.textContent = AudioEngine.muted ? '🔇 静音' : '🔊 音效';
}

const muteBtn = document.getElementById('muteBtn');
if (muteBtn) {
    muteBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        AudioEngine.toggleMute();
    });
}
updateMuteButton();

function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
    // 固定视口宽度为 2000 世界单位，让地图需要滚动才能看完
    scale = canvas.width / 2000;
}

function getCameraX() {
    const me = getMyHero();
    if (!me) return MAP_W / 2;
    const halfW = canvas.width / 2 / scale;
    return Math.max(halfW, Math.min(MAP_W - halfW, me.x));
}

function getCameraY() {
    const me = getMyHero();
    if (!me) return MAP_H / 2;
    const halfH = canvas.height / 2 / scale;
    return Math.max(halfH, Math.min(MAP_H - halfH, me.y));
}
window.addEventListener('resize', resize);
resize();

function worldToScreen(x, y) {
    const cx = getCameraX();
    const cy = getCameraY();
    let sx = canvas.width / 2 + (x - cx) * scale;
    let sy = canvas.height / 2 + (y - cy) * scale;
    if (shakeTimer > 0) {
        sx += (Math.random() - 0.5) * shakeIntensity;
        sy += (Math.random() - 0.5) * shakeIntensity;
    }
    return { x: sx, y: sy };
}

function screenToWorld(x, y) {
    const cx = getCameraX();
    const cy = getCameraY();
    return {
        x: cx + (x - canvas.width / 2) / scale,
        y: cy + (y - canvas.height / 2) / scale
    };
}

function connect() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(`${protocol}//${window.location.host}`);
    connectionEl.classList.remove('hidden');

    ws.onopen = () => {
        connectionEl.classList.add('hidden');
        if (selectedRole) ws.send(JSON.stringify({ type: 'join', role: selectedRole }));
    };

    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data.type === 'hello') {
            console.log(data.message);
        } else if (data.type === 'joined') {
            myTeam = data.team;
            myHeroId = data.id;
        } else if (data.type === 'player_count') {
            document.getElementById('statusText').style.display = 'block';
            document.getElementById('statusText').textContent = `已加入 (${data.count}/${data.max}) — 点Dev面板生成AI开局`;
        } else if (data.type === 'start') {
            menuEl.classList.add('hidden');
            hudEl.style.display = 'block';
            document.getElementById('status').textContent = data.message;
        } else if (data.type === 'end') {
            gameoverEl.classList.remove('hidden');
            hudEl.style.display = 'none';
            document.getElementById('resultText').textContent = data.winner + '胜利！';
            document.getElementById('resultDetail').textContent = '15 秒后房间自动重置，可重新加入';
            if (data.stats) renderEndStats(data.stats);
        } else if (data.type === 'reset') {
            gameState = null;
            gameoverEl.classList.add('hidden');
            menuEl.classList.remove('hidden');
            document.querySelectorAll('.hero-card').forEach(c => c.classList.remove('selected'));
            selectedRole = null;
            document.getElementById('joinBtn').disabled = true;
            myTeam = null;
            myHeroId = null;
        } else if (data.type === 'shake') {
            shakeTimer = data.duration || 0.2;
            shakeIntensity = data.intensity || 5;
            triggerHitStop(0.1);
        } else if (data.type === 'sound') {
            AudioEngine.play(data.soundType, data);
        } else if (data.type === 'error') {
            alert(data.message);
        } else if (data.type === 'damage_number') {
            damageNumbers.push({
                x: data.x, y: data.y,
                amount: data.amount,
                isCrit: data.isCrit,
                life: 0.8,
                vy: -80
            });
            if (data.isCrit) triggerHitStop(0.06);
        } else if (data.state !== undefined) {
            if (hitStopTimer > 0) pendingState = data;
            else gameState = data;
        }
    };

    ws.onclose = () => {
        connectionEl.textContent = '连接已断开';
        connectionEl.classList.remove('hidden');
    };
}

// 英雄选择
for (const card of document.querySelectorAll('.hero-card')) {
    card.addEventListener('click', () => {
        document.querySelectorAll('.hero-card').forEach(c => c.classList.remove('selected'));
        card.classList.add('selected');
        selectedRole = card.dataset.role;
        document.getElementById('joinBtn').disabled = false;
    });
}

document.getElementById('joinBtn').addEventListener('click', () => {
    if (!selectedRole || !ws) return;
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'join', role: selectedRole }));
        document.getElementById('joinBtn').textContent = '等待对手...';
        document.getElementById('joinBtn').disabled = true;
        document.getElementById('statusText').textContent = '已加入，等待其他玩家或用Dev面板生成AI';
        document.getElementById('statusText').style.display = 'block';
    }
});

document.getElementById('restartBtn').addEventListener('click', () => window.location.reload());

connect();

// ==================== PC 键鼠输入 ====================
window.addEventListener('keydown', e => {
    keys[e.key.toLowerCase()] = true;
    const key = e.key.toLowerCase();
    if (['q', 'w', 'e', 'r'].includes(key)) castSkill(key);
    if (key === ' ' || key === 'j') basicAttack();
    if (key === 'd') startRecall();
    if (key === 't') globalTeleport();
});
window.addEventListener('keyup', e => keys[e.key.toLowerCase()] = false);

function startRecall() {
    if (!gameState || gameState.state !== 'playing' || !ws) return;
    const me = getMyHero();
    if (!me || me.dead) return;
    ws.send(JSON.stringify({ type: 'recall' }));
}

function globalTeleport() {
    if (!gameState || gameState.state !== 'playing' || !ws) return;
    const me = getMyHero();
    if (!me || me.dead || me.level < 3) return;
    // 找最近的己方防御塔或小兵
    let best = null, bestD = Infinity;
    for (const t of gameState.towers || []) {
        if (t.dead || t.team !== myTeam) continue;
        const d = Math.hypot(me.x - t.x, me.y - t.y);
        if (d < bestD) { bestD = d; best = t; }
    }
    for (const m of gameState.minions || []) {
        if (m.dead || m.team !== myTeam) continue;
        const d = Math.hypot(me.x - m.x, me.y - m.y);
        if (d < bestD) { bestD = d; best = m; }
    }
    if (best) ws.send(JSON.stringify({ type: 'global_tp', targetId: best.id }));
}

function devCommand(type) {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    ws.send(JSON.stringify({ type }));
}

function devSpawnBot(role) {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    // 游戏未开始时用默认坐标
    const worldPos = gameState ? screenToWorld(mouseX, mouseY) : { x: 5500, y: 7000 };
    ws.send(JSON.stringify({ type: 'dev_spawn_bot', role, x: worldPos.x, y: worldPos.y }));
}

window.addEventListener('mousemove', e => {
    mouseX = e.clientX;
    mouseY = e.clientY;
});

canvas.addEventListener('contextmenu', e => e.preventDefault());

canvas.addEventListener('mousedown', e => {
    if (!gameState || gameState.state !== 'playing' || !ws) return;
    const me = getMyHero();
    const worldPos = screenToWorld(e.clientX, e.clientY);

    if (e.button === 2) {
        // 右键移动（引导中取消引导）
        if (me && me.channeling) {
            ws.send(JSON.stringify({ type: 'cancel_channel' }));
            return;
        }
        ws.send(JSON.stringify({ type: 'move', x: worldPos.x, y: worldPos.y }));
    } else if (e.button === 0) {
        // 左键普攻
        if (me && me.channeling) return;
        const target = findTargetUnderMouse(worldPos);
        if (target) {
            ws.send(JSON.stringify({ type: 'attack', targetId: target.id }));
        }
    }
});

for (const skillEl of document.querySelectorAll('.skill')) {
    skillEl.addEventListener('click', () => {
        const slot = skillEl.id.replace('skill', '').toLowerCase();
        castSkill(slot);
    });
}

function findTargetUnderMouse(worldPos) {
    if (!gameState) return null;
    let best = null, bestD = Infinity;
    for (const e of [...gameState.heroes, ...gameState.minions, ...gameState.towers, ...gameState.monsters]) {
        if (e.dead || e.team === myTeam) continue;
        const d = Math.hypot(e.x - worldPos.x, e.y - worldPos.y);
        if (d < e.radius + 50 && d < bestD) { bestD = d; best = e; }
    }
    return best;
}

function getMouseWorld() {
    return screenToWorld(mouseX, mouseY);
}

function castSkill(slot) {
    if (!gameState || gameState.state !== 'playing' || !ws) return;
    const me = getMyHero();
    if (!me || me.dead) return;
    // 引导中按 R 取消引导
    if (me.channeling && me.role === 'archer' && slot === 'r') {
        ws.send(JSON.stringify({ type: 'cancel_channel' }));
        return;
    }
    if (me.channeling) return;
    const skill = me.skills[slot];
    if (!skill) return;
    if (skill.locked) {
        showNotice('大招 3 级解锁');
        return;
    }
    const target = findTargetUnderMouse(getMouseWorld());
    const worldPos = getMouseWorld();
    const isSkillShot = (slot === 'q') || (slot === 'w' && me.role === 'mage') || (slot === 'r' && me.role === 'archer');
    ws.send(JSON.stringify({
        type: 'skill',
        slot: slot,
        x: worldPos.x,
        y: worldPos.y,
        targetId: (isSkillShot || !target) ? null : target.id
    }));
}

let noticeTimer = null;
function showNotice(text) {
    const el = document.getElementById('status');
    const old = el.textContent;
    el.textContent = text;
    el.style.color = '#f55';
    if (noticeTimer) clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => {
        el.textContent = old;
        el.style.color = '#ffd700';
    }, 1500);
}

function basicAttack() {
    if (!gameState || gameState.state !== 'playing' || !ws) return;
    const me = getMyHero();
    if (!me || me.dead) return;
    const target = findTargetUnderMouse(getMouseWorld());
    // 有目标发目标ID，没目标发-1让服务器自动选择最近敌人
    ws.send(JSON.stringify({ type: 'attack', targetId: target ? target.id : -1 }));
}

// WASD 持续移动驱动
let lastMoveSend = 0;
function sendWASDMove() {
    if (!gameState || gameState.state !== 'playing' || !ws) return;
    const me = getMyHero();
    if (!me || me.dead || me.channeling) return;

    let dx = 0, dy = 0;
    // 技能键不触发行走
    if (!keys['q'] && !keys['w'] && !keys['e'] && !keys['r']) {
        if (keys['w'] || keys['arrowup']) dy -= 1;
        if (keys['s'] || keys['arrowdown']) dy += 1;
        if (keys['a'] || keys['arrowleft']) dx -= 1;
        if (keys['d'] || keys['arrowright']) dx += 1;
    }
    if (dx === 0 && dy === 0) return;

    const now = Date.now();
    if (now - lastMoveSend < 50) return;
    lastMoveSend = now;

    const len = Math.hypot(dx, dy);
    const targetX = me.x + dx / len * 200;
    const targetY = me.y + dy / len * 200;
    ws.send(JSON.stringify({ type: 'move', x: targetX, y: targetY }));
}

// ==================== 渲染 ====================
function drawCircle(x, y, radius, color, border, flash) {
    const pos = worldToScreen(x, y);
    const r = radius * scale;
    ctx.beginPath();
    ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2);
    ctx.fillStyle = flash ? '#fff' : color;
    ctx.fill();
    if (border) {
        ctx.strokeStyle = border;
        ctx.lineWidth = 2;
        ctx.stroke();
    }
}

function drawShadow(x, y, radius) {
    const pos = worldToScreen(x, y + radius * 0.35);
    const rx = radius * scale;
    const ry = radius * scale * 0.35;
    ctx.beginPath();
    ctx.ellipse(pos.x, pos.y, rx, ry, 0, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(0, 0, 0, 0.22)';
    ctx.fill();
}

function drawHealthBar(x, y, radius, hp, maxHp, team) {
    const pos = worldToScreen(x, y);
    const width = Math.max(35, radius * 2 * scale);
    const height = 6;
    const bx = pos.x - width / 2;
    const by = pos.y - radius * scale - 10;
    ctx.fillStyle = '#000';
    ctx.fillRect(bx, by, width, height);
    ctx.fillStyle = team === 0 ? '#4af' : '#f55';
    ctx.fillRect(bx, by, width * (hp / maxHp), height);
}

function drawFallbackMap() {
    const tl = worldToScreen(0, 0);
    const br = worldToScreen(MAP_W, MAP_H);
    ctx.fillStyle = '#224422';
    ctx.fillRect(tl.x, tl.y, br.x - tl.x, br.y - tl.y);

    // 上路
    const topStart = worldToScreen(0, 7000);
    const topEnd = worldToScreen(MAP_W, 7000);
    ctx.strokeStyle = '#5a4a38'; ctx.lineWidth = 140 * scale; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(topStart.x, topStart.y); ctx.lineTo(topEnd.x, topEnd.y); ctx.stroke();
    // 下路
    const botStart = worldToScreen(0, 3000);
    const botEnd = worldToScreen(MAP_W, 3000);
    ctx.beginPath(); ctx.moveTo(botStart.x, botStart.y); ctx.lineTo(botEnd.x, botEnd.y); ctx.stroke();
    // 垂直连接
    const leftTop = worldToScreen(1000, 5000);
    const leftBot = worldToScreen(1000, 3000);
    const leftUp = worldToScreen(1000, 7000);
    ctx.lineWidth = 140 * scale;
    ctx.beginPath(); ctx.moveTo(leftTop.x, leftTop.y); ctx.lineTo(leftUp.x, leftUp.y); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(leftTop.x, leftTop.y); ctx.lineTo(leftBot.x, leftBot.y); ctx.stroke();
    const rightTop = worldToScreen(9000, 5000);
    const rightUp = worldToScreen(9000, 7000);
    const rightBot = worldToScreen(9000, 3000);
    ctx.beginPath(); ctx.moveTo(rightTop.x, rightTop.y); ctx.lineTo(rightUp.x, rightUp.y); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(rightTop.x, rightTop.y); ctx.lineTo(rightBot.x, rightBot.y); ctx.stroke();

    // 基地
    const blueBase = worldToScreen(1000, MAP_H / 2);
    const redBase = worldToScreen(9000, MAP_H / 2);
    ctx.fillStyle = 'rgba(50,100,255,0.2)';
    ctx.beginPath(); ctx.arc(blueBase.x, blueBase.y, 180 * scale, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(255,50,50,0.2)';
    ctx.beginPath(); ctx.arc(redBase.x, redBase.y, 180 * scale, 0, Math.PI * 2); ctx.fill();

    // 泉水
    ctx.fillStyle = 'rgba(100, 200, 255, 0.25)';
    ctx.beginPath(); ctx.arc(blueBase.x, blueBase.y, 250 * scale, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgba(255, 100, 100, 0.25)';
    ctx.beginPath(); ctx.arc(redBase.x, redBase.y, 250 * scale, 0, Math.PI * 2); ctx.fill();
}

function drawMap() {
    if (!mapData) {
        drawFallbackMap();
        return;
    }

    // 地形
    for (const t of mapData.terrain || []) {
        const tl = worldToScreen(t.x, t.y);
        const br = worldToScreen(t.x + t.w, t.y + t.h);
        // 草地纹理
        ctx.fillStyle = '#2a4a22';
        ctx.fillRect(tl.x, tl.y, br.x - tl.x, br.y - tl.y);
        // 随机草点增加纹理感
        for (let i = 0; i < 60; i++) {
            const gx = t.x + Math.random() * t.w;
            const gy = t.y + Math.random() * t.h;
            const gp = worldToScreen(gx, gy);
            ctx.fillStyle = `rgba(${30+Math.random()*30},${50+Math.random()*40},${20+Math.random()*20},0.4)`;
            ctx.fillRect(gp.x, gp.y, 2 * scale, 2 * scale);
        }
    }

    // 河道（地图中央斜穿）
    const riverPoints = [
        {x: 1000, y: 2000}, {x: 2500, y: 4500}, {x: 5000, y: 5000},
        {x: 7500, y: 5500}, {x: 9000, y: 8000}
    ];
    ctx.lineWidth = 280 * scale;
    ctx.strokeStyle = 'rgba(30, 100, 140, 0.45)';
    ctx.lineCap = 'round';
    ctx.beginPath();
    for (let i = 0; i < riverPoints.length; i++) {
        const rp = worldToScreen(riverPoints[i].x, riverPoints[i].y);
        i === 0 ? ctx.moveTo(rp.x, rp.y) : ctx.lineTo(rp.x, rp.y);
    }
    ctx.stroke();
    // 河道高光线
    ctx.lineWidth = 80 * scale;
    ctx.strokeStyle = 'rgba(80, 160, 200, 0.5)';
    ctx.beginPath();
    for (let i = 0; i < riverPoints.length; i++) {
        const rp = worldToScreen(riverPoints[i].x, riverPoints[i].y);
        i === 0 ? ctx.moveTo(rp.x, rp.y) : ctx.lineTo(rp.x, rp.y);
    }
    ctx.stroke();
    // 道路两侧碎石过渡带
    for (const r of mapData.roads || []) {
        const tl = worldToScreen(r.x - 50, r.y - 10);
        const br = worldToScreen(r.x + r.w + 50, r.y + r.h + 10);
        ctx.fillStyle = '#4a3a2a';
        ctx.fillRect(tl.x, tl.y, br.x - tl.x, br.y - tl.y);
    }
    // 道路
    for (const r of mapData.roads || []) {
        const tl = worldToScreen(r.x, r.y);
        const br = worldToScreen(r.x + r.w, r.y + r.h);
        ctx.fillStyle = '#5a4a38';
        ctx.fillRect(tl.x, tl.y, br.x - tl.x, br.y - tl.y);
        // 路面纹理线
        ctx.strokeStyle = '#4a3a28';
        ctx.lineWidth = 1;
        for (let i = 0; i < r.w; i += 120) {
            const lx = worldToScreen(r.x + i, r.y).x;
            ctx.beginPath();
            ctx.moveTo(lx, tl.y);
            ctx.lineTo(lx, br.y);
            ctx.stroke();
        }
    }

    // 野区装饰：散布树木/石块（固定种子避免闪烁）
    const jungleSeed = 42;
    function pseudoRandom(x, y) { return ((Math.sin(x * 12.9898 + y * 78.233 + jungleSeed) * 43758.5453) % 1 + 1) % 1; }
    for (let gx = 0; gx < MAP_W; gx += 400) {
        for (let gy = 0; gy < MAP_H; gy += 400) {
            // 跳过道路区域
            const onRoad = (mapData.roads || []).some(r => gx > r.x - 150 && gx < r.x + r.w + 150 && gy > r.y - 150 && gy < r.y + r.h + 150);
            const onBase = (mapData.bases || []).some(b => Math.hypot(gx - b.x, gy - b.y) < b.radius + 300);
            if (onRoad || onBase) continue;
            const rv = pseudoRandom(gx, gy);
            if (rv > 0.65) {
                const pos = worldToScreen(gx + (rv - 0.5) * 200, gy + pseudoRandom(gy, gx) * 200);
                const size = 6 + rv * 10 * scale;
                if (rv > 0.85) {
                    // 古树
                    ctx.fillStyle = '#1a3a1a';
                    ctx.beginPath(); ctx.arc(pos.x, pos.y, size, 0, Math.PI * 2); ctx.fill();
                    ctx.fillStyle = '#2a5a2a';
                    ctx.beginPath(); ctx.arc(pos.x - size * 0.3, pos.y - size * 0.3, size * 0.6, 0, Math.PI * 2); ctx.fill();
                } else if (rv > 0.75) {
                    // 石块/遗迹
                    ctx.fillStyle = '#555';
                    ctx.fillRect(pos.x - size * 0.5, pos.y - size * 0.3, size, size * 0.6);
                } else {
                    // 灌木
                    ctx.fillStyle = '#2a4a2a';
                    ctx.beginPath(); ctx.arc(pos.x, pos.y, size * 0.7, 0, Math.PI * 2); ctx.fill();
                }
            }
        }
    }

    // 野区水塘（几个固定位置）
    const ponds = [
        { x: 2000, y: 6000, r: 350 },
        { x: 8000, y: 4000, r: 300 },
        { x: 3500, y: 3500, r: 250 },
        { x: 6500, y: 6500, r: 280 }
    ];
    for (const p of ponds) {
        const pos = worldToScreen(p.x, p.y);
        ctx.fillStyle = 'rgba(30, 80, 140, 0.35)';
        ctx.beginPath(); ctx.arc(pos.x, pos.y, p.r * scale, 0, Math.PI * 2); ctx.fill();
        ctx.strokeStyle = 'rgba(50, 120, 180, 0.5)';
        ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(pos.x, pos.y, p.r * scale, 0, Math.PI * 2); ctx.stroke();
    }

    // 地图边界——悬崖+迷雾
    const borderW = 400;
    // 上边
    const topTl = worldToScreen(0, MAP_H - borderW);
    const topBr = worldToScreen(MAP_W, MAP_H);
    const gradTop = ctx.createLinearGradient(0, topTl.y, 0, topBr.y);
    gradTop.addColorStop(0, 'rgba(40,30,20,0)');
    gradTop.addColorStop(0.3, 'rgba(40,30,20,0.6)');
    gradTop.addColorStop(1, 'rgba(20,15,10,0.9)');
    ctx.fillStyle = gradTop;
    ctx.fillRect(topTl.x, topTl.y, topBr.x - topTl.x, topBr.y - topTl.y);
    // 下边
    const botTl = worldToScreen(0, 0);
    const botBr = worldToScreen(MAP_W, borderW);
    const gradBot = ctx.createLinearGradient(0, botTl.y, 0, botBr.y);
    gradBot.addColorStop(0, 'rgba(20,15,10,0.9)');
    gradBot.addColorStop(0.7, 'rgba(40,30,20,0.6)');
    gradBot.addColorStop(1, 'rgba(40,30,20,0)');
    ctx.fillStyle = gradBot;
    ctx.fillRect(botTl.x, botTl.y, botBr.x - botTl.x, botBr.y - botTl.y);
    // 左边
    const leftTl = worldToScreen(0, 0);
    const leftBr = worldToScreen(borderW, MAP_H);
    const gradLeft = ctx.createLinearGradient(leftTl.x, 0, leftBr.x, 0);
    gradLeft.addColorStop(0, 'rgba(20,15,10,0.9)');
    gradLeft.addColorStop(0.7, 'rgba(40,30,20,0.6)');
    gradLeft.addColorStop(1, 'rgba(40,30,20,0)');
    ctx.fillStyle = gradLeft;
    ctx.fillRect(leftTl.x, leftTl.y, leftBr.x - leftTl.x, leftBr.y - leftTl.y);
    // 右边
    const rightTl = worldToScreen(MAP_W - borderW, 0);
    const rightBr = worldToScreen(MAP_W, MAP_H);
    const gradRight = ctx.createLinearGradient(rightTl.x, 0, rightBr.x, 0);
    gradRight.addColorStop(0, 'rgba(40,30,20,0)');
    gradRight.addColorStop(0.7, 'rgba(40,30,20,0.6)');
    gradRight.addColorStop(1, 'rgba(20,15,10,0.9)');
    ctx.fillStyle = gradRight;
    ctx.fillRect(rightTl.x, rightTl.y, rightBr.x - rightTl.x, rightBr.y - rightTl.y);

    // 边界灵力迷雾粒子
    for (let i = 0; i < 30; i++) {
        const mx = (i * 340 + Date.now() * 0.01) % MAP_W;
        const my = (i * 210) % 120;
        const pos = worldToScreen(mx, my < 60 ? my : MAP_H - (my - 60));
        ctx.fillStyle = 'rgba(180, 200, 255, 0.15)';
        ctx.beginPath(); ctx.arc(pos.x, pos.y, 20 * scale, 0, Math.PI * 2); ctx.fill();
    }
    // 基地水晶发光特效
    for (const b of mapData.bases || []) {
        const pos = worldToScreen(b.x, b.y);
        const color = b.team === 0 ? 'rgba(50,150,255,' : 'rgba(255,80,80,';
        // 外层光晕
        for (let i = 3; i > 0; i--) {
            ctx.fillStyle = color + (0.05 * i) + ')';
            ctx.beginPath();
            ctx.arc(pos.x, pos.y, (b.radius + i * 50) * scale, 0, Math.PI * 2);
            ctx.fill();
        }
        // 水晶本体
        const glow = 0.5 + 0.3 * Math.sin(Date.now() * 0.003);
        ctx.fillStyle = color + glow + ')';
        ctx.beginPath(); ctx.arc(pos.x, pos.y, b.radius * scale, 0, Math.PI * 2); ctx.fill();
        ctx.fillStyle = 'rgba(255,255,255,0.3)';
        ctx.beginPath(); ctx.arc(pos.x - b.radius*0.2*scale, pos.y - b.radius*0.2*scale, b.radius*0.3*scale, 0, Math.PI*2); ctx.fill();
    }
    // 泉水
    for (const f of mapData.fountains || []) {
        const pos = worldToScreen(f.x, f.y);
        const fColor = f.team === 0 ? 'rgba(80,180,255,' : 'rgba(255,100,100,';
        // 泉水波动环
        for (let w = 0; w < 3; w++) {
            const waveR = (f.radius + 20 + w * 30 + (Date.now()*0.05 % 40)) * scale;
            ctx.strokeStyle = fColor + Math.max(0, 0.3 - w*0.1) + ')';
            ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, waveR, 0, Math.PI * 2); ctx.stroke();
        }
        ctx.fillStyle = fColor + '0.2)';
        ctx.beginPath(); ctx.arc(pos.x, pos.y, f.radius * scale, 0, Math.PI * 2); ctx.fill();
        // 治愈粒子
        for (let p = 0; p < 8; p++) {
            const pa = (Date.now() * 0.002 + p) % (Math.PI * 2);
            const pr = f.radius * 0.6 * scale;
            const px = pos.x + Math.cos(pa) * pr;
            const py = pos.y + Math.sin(pa) * pr * 0.4;
            ctx.fillStyle = fColor + '0.6)';
            ctx.beginPath(); ctx.arc(px, py, 3 * scale, 0, Math.PI * 2); ctx.fill();
        }
    }
    // 草丛
    for (const b of mapData.bushes || []) {
        const pos = worldToScreen(b.x, b.y);
        ctx.fillStyle = 'rgba(30, 100, 30, 0.6)';
        ctx.fillRect(pos.x, pos.y, b.w * scale, b.h * scale);
        ctx.strokeStyle = 'rgba(50, 150, 50, 0.4)';
        ctx.lineWidth = 2;
        ctx.strokeRect(pos.x, pos.y, b.w * scale, b.h * scale);
    }
    // 墙体障碍
    for (const w of mapData.walls || []) {
        const pos = worldToScreen(w.x, w.y);
        ctx.fillStyle = 'rgba(80, 80, 80, 0.85)';
        ctx.fillRect(pos.x, pos.y, w.w * scale, w.h * scale);
        ctx.strokeStyle = '#999';
        ctx.lineWidth = 2;
        ctx.strokeRect(pos.x, pos.y, w.w * scale, w.h * scale);
    }
}

function render() {
    ctx.fillStyle = '#1a2a1a';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    drawMap();

    if (!gameState) { requestAnimationFrame(render); return; }

    // 技能效果
    for (const e of gameState.effects || []) {
        const pos = worldToScreen(e.x, e.y);
        const alpha = Math.max(0, e.life / (e.maxLife || 1));
        const progress = e.maxLife ? 1 - alpha : 0;

        if (e.type === 'ring_expand') {
            // 环形波纹：从中心向外扩散
            ctx.strokeStyle = `rgba(255, 200, 50, ${alpha * 0.7})`;
            ctx.lineWidth = 6 * alpha + 2;
            const r = e.radius * (1 - alpha * 0.3) * scale;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.stroke();
        } else if (e.type === 'shield_glow') {
            // 不动如山护盾：金色阵法
            const r = e.radius * scale;
            ctx.strokeStyle = `rgba(255, 215, 0, ${alpha * 0.6})`;
            ctx.lineWidth = 3;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.stroke();
            // 内圈脉冲
            const innerR = r * (0.6 + 0.4 * Math.sin(Date.now() * 0.005));
            ctx.fillStyle = `rgba(255, 215, 0, ${alpha * 0.15})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, innerR, 0, Math.PI * 2); ctx.fill();
        } else if (e.type === 'warrior_q_dash') {
            // 冲刺拖尾
            const r = e.radius * scale * alpha;
            ctx.fillStyle = `rgba(255, 150, 100, ${alpha * 0.4})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.fill();
        } else if (e.type === 'warrior_q_dust') {
            // 扬尘粒子
            const r = e.radius * scale * (1 - alpha * 0.5);
            ctx.fillStyle = `rgba(200, 180, 150, ${alpha * 0.5})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.fill();
            // 扩散子粒子
            for (let i = 0; i < 5; i++) {
                const angle = (i / 5) * Math.PI * 2 + progress * 2;
                const dist = r * 1.5 * progress;
                const px = pos.x + Math.cos(angle) * dist;
                const py = pos.y + Math.sin(angle) * dist;
                ctx.fillStyle = `rgba(180, 160, 130, ${alpha * 0.3})`;
                ctx.beginPath(); ctx.arc(px, py, 4 * scale * alpha, 0, Math.PI * 2); ctx.fill();
            }
        } else if (e.type === 'warn_circle') {
            // 警告圈：红色半透明脉冲
            const pulse = 0.7 + 0.3 * Math.sin(Date.now() * 0.01);
            ctx.strokeStyle = `rgba(255, 50, 50, ${alpha * pulse})`;
            ctx.lineWidth = 3;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, e.radius * scale, 0, Math.PI * 2); ctx.stroke();
            ctx.fillStyle = `rgba(255, 50, 50, ${alpha * pulse * 0.15})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, e.radius * scale, 0, Math.PI * 2); ctx.fill();
        } else if (e.type === 'burst') {
            // 爆发特效：瞬间闪光
            const r = e.radius * scale * (1 + alpha * 0.3);
            ctx.fillStyle = `rgba(255, 200, 0, ${alpha * 0.5})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.fill();
            ctx.strokeStyle = `rgba(255, 255, 255, ${alpha * 0.8})`;
            ctx.lineWidth = 4 * alpha;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, r * 0.5, 0, Math.PI * 2); ctx.stroke();
        } else if (e.type === 'vortex') {
            // 黑洞漩涡：多层同心圆旋转
            for (let layer = 0; layer < 3; layer++) {
                const layerR = e.radius * scale * (1 - layer * 0.25) * (1 - progress * 0.6);
                const rotOffset = (Date.now() * 0.002 + layer * 2) % (Math.PI * 2);
                ctx.strokeStyle = `rgba(80, 30, 120, ${alpha * (0.5 - layer * 0.12)})`;
                ctx.lineWidth = 3;
                ctx.beginPath();
                for (let i = 0; i <= 32; i++) {
                    const a = (i / 32) * Math.PI * 2 + rotOffset;
                    const r = layerR * (0.8 + 0.2 * Math.sin(i * 3));
                    const px = pos.x + Math.cos(a) * r;
                    const py = pos.y + Math.sin(a) * r;
                    i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
                }
                ctx.closePath(); ctx.stroke();
            }
        } else if (e.type === 'ghost_shadow') {
            // 残影：半透明英雄轮廓
            ctx.fillStyle = `rgba(200, 200, 255, ${alpha * 0.5})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, e.radius * scale, 0, Math.PI * 2); ctx.fill();
            ctx.strokeStyle = `rgba(255, 255, 255, ${alpha * 0.7})`;
            ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, e.radius * scale, 0, Math.PI * 2); ctx.stroke();
        } else if (e.type === 'arrow_rain') {
            // 扇形箭雨
            ctx.fillStyle = `rgba(200, 180, 100, ${alpha * 0.15})`;
            ctx.beginPath();
            ctx.moveTo(pos.x, pos.y);
            const coneAngle = Math.PI / 6;
            ctx.arc(pos.x, pos.y, e.radius * scale, -coneAngle, coneAngle);
            ctx.closePath(); ctx.fill();
            // 随机箭矢粒子
            for (let i = 0; i < 8; i++) {
                const a = (Math.random() - 0.5) * coneAngle * 2;
                const d = Math.random() * e.radius * scale;
                const px = pos.x + Math.cos(a) * d;
                const py = pos.y + Math.sin(a) * d;
                ctx.strokeStyle = `rgba(255, 220, 150, ${alpha * 0.5})`;
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(px, py);
                ctx.lineTo(px + Math.cos(a) * 15 * scale, py + Math.sin(a) * 15 * scale);
                ctx.stroke();
            }
        } else if (e.type === 'mage_q_trail') {
            // 灵符拖尾
            ctx.fillStyle = `rgba(150, 100, 255, ${alpha * 0.3})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, e.radius * scale, 0, Math.PI * 2); ctx.fill();
        } else if (['ult', 'aoe', 'dash', 'meteor_hit'].includes(e.type)) {
            const colors = { ult: '255,80,0', aoe: '255,150,0', dash: '200,200,255', meteor_hit: '255,50,0' };
            ctx.fillStyle = `rgba(${colors[e.type] || '255,255,255'}, ${alpha * 0.3})`;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, e.radius * scale, 0, Math.PI * 2); ctx.fill();
        }
    }

    // 按 Y 轴排序绘制所有实体（Y 越大越靠前），产生 2D 伪深度
    const renderList = [];
    for (const m of gameState.monsters || []) {
        if (!m.dead) renderList.push({ kind: 'monster', e: m, radius: m.type === 'camp' ? (m.campType === 'red_buff' || m.campType === 'blue_buff' ? 35 : 25) : (m.type === 'baron' ? 75 : 60) });
    }
    for (const t of gameState.towers || []) {
        if (!t.dead) {
            const r = t.tier === 'crystal' ? 65 : (t.tier === 'inner' ? 50 : 45);
            renderList.push({ kind: 'tower', e: t, radius: r });
        }
    }
    for (const m of gameState.minions || []) {
        if (!m.dead) renderList.push({ kind: 'minion', e: m, radius: m.minionType === 'cannon' ? 28 : 22 });
    }
    for (const h of gameState.heroes || []) {
        if (!h.dead) renderList.push({ kind: 'hero', e: h, radius: 35 });
    }
    renderList.sort((a, b) => a.e.y - b.e.y);

    for (const item of renderList) {
        const e = item.e;
        const r = item.radius;
        drawShadow(e.x, e.y, r);
        if (item.kind === 'monster') {
            let color = e.type === 'baron' ? '#aa00ff' : '#ffaa00';
            if (e.type === 'camp') {
                const campColors = { red_buff: '#ff4444', blue_buff: '#4444ff', chijia: '#cc6644', shanhao: '#996633', liezhi: '#ff8844', luxi_yebao: '#88aa44' };
                color = campColors[e.campType] || '#888';
            }
            drawCircle(e.x, e.y, r, color, '#fff', e.hitFlash);
            drawHealthBar(e.x, e.y, r, e.hp, e.maxHp, 2);
        } else if (item.kind === 'tower') {
            const colors = { outer: '#3355ff', inner: '#2244cc', crystal: '#112288' };
            const redColors = { outer: '#ff3333', inner: '#cc2222', crystal: '#881111' };
            const base = e.team === 0 ? (colors[e.tier] || '#3355ff') : (redColors[e.tier] || '#ff3333');
            drawCircle(e.x, e.y, r, base, '#fff', e.hitFlash);
            // 二塔护盾指示
            if (e.shieldStacks > 0) {
                const pos = worldToScreen(e.x, e.y);
                ctx.fillStyle = 'rgba(255,255,255,0.3)';
                ctx.beginPath(); ctx.arc(pos.x, pos.y, r * scale * 1.3, 0, Math.PI * 2 * (e.shieldStacks / 2)); ctx.fill();
            }
            drawHealthBar(e.x, e.y, r, e.hp, e.maxHp, e.team);
        } else if (item.kind === 'minion') {
            const isCannon = e.minionType === 'cannon';
            const baseColor = e.team === 0 ? '#7799ff' : '#ff7777';
            const color = isCannon ? (e.team === 0 ? '#3355cc' : '#cc3333') : baseColor;
            const border = e.berserk ? '#ff0' : (e.frenzyBuffed ? '#f00' : '#000');
            const size = isCannon ? r * 1.3 : r;
            drawCircle(e.x, e.y, size, color, border, e.hitFlash);
            drawHealthBar(e.x, e.y, r, e.hp, e.maxHp, e.team);
        } else if (item.kind === 'hero') {
            const isMe = e.id === myHeroId;
            const color = e.team === 0 ? '#4488ff' : '#ff4444';
            const border = isMe ? '#ffd700' : (e.isBot ? '#aaa' : '#fff');
            drawCircle(e.x, e.y, r, color, border, e.hitFlash);
            drawHealthBar(e.x, e.y, r, e.hp, e.maxHp, e.team);
            const pos = worldToScreen(e.x, e.y);

            // 不动如山护盾辉光
            if (e.ccImmune) {
                const glowR = r * 1.6 * scale;
                ctx.strokeStyle = 'rgba(255, 215, 0, 0.5)';
                ctx.lineWidth = 3;
                ctx.beginPath(); ctx.arc(pos.x, pos.y, glowR, 0, Math.PI * 2); ctx.stroke();
                ctx.fillStyle = 'rgba(255, 215, 0, 0.08)';
                ctx.beginPath(); ctx.arc(pos.x, pos.y, glowR, 0, Math.PI * 2); ctx.fill();
            }

            // 引导中提示（万箭齐发/万象天引）
            if (e.channeling) {
                ctx.strokeStyle = 'rgba(255, 100, 50, 0.7)';
                ctx.lineWidth = 2;
                const chR = r * 1.4 * scale;
                ctx.beginPath(); ctx.arc(pos.x, pos.y, chR, 0, Math.PI * 2); ctx.stroke();
            }

            // 护盾条
            if (e.shield > 0) {
                const width = Math.max(35, r * 2 * scale);
                const bx = pos.x - width / 2;
                const by = pos.y - r * scale - 14;
                ctx.fillStyle = 'rgba(255,255,255,0.6)';
                ctx.fillRect(bx, by, width * (e.shield / (e.maxHp * 0.15)), 3);
            }

            // 定身
            if (e.rooted) {
                ctx.strokeStyle = 'rgba(255, 50, 50, 0.8)';
                ctx.lineWidth = 2;
                const rx = r * 1.25 * scale;
                ctx.beginPath(); ctx.arc(pos.x, pos.y, rx, 0, Math.PI * 2); ctx.stroke();
            }

            // 隐匿（蓝紫色光晕）
            if (e.stealthTimer > 0) {
                ctx.fillStyle = 'rgba(100, 100, 255, 0.2)';
                ctx.beginPath(); ctx.arc(pos.x, pos.y, r * 1.5 * scale, 0, Math.PI * 2); ctx.fill();
            }

            // 蓄力中（收缩圈）
            if (e.charging) {
                ctx.strokeStyle = 'rgba(0, 200, 255, 0.7)';
                ctx.lineWidth = 3;
                ctx.beginPath(); ctx.arc(pos.x, pos.y, r * 1.3 * scale, 0, Math.PI * 2); ctx.stroke();
            }

            // 减速（黄色底色）
            if (e.slowTimer > 0) {
                ctx.fillStyle = 'rgba(255, 255, 0, 0.1)';
                ctx.beginPath(); ctx.arc(pos.x, pos.y, r * 1.4 * scale, 0, Math.PI * 2); ctx.fill();
            }

            const len = 50 * scale;
            ctx.strokeStyle = '#fff'; ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(pos.x, pos.y);
            ctx.lineTo(pos.x + Math.cos(e.faceAngle) * len, pos.y + Math.sin(e.faceAngle) * len);
            ctx.stroke();

            // 回城引导圈
            if (e.isRecalling) {
                const progress = e.recallTimer / e.recallDuration;
                ctx.strokeStyle = '#0f0';
                ctx.lineWidth = 4;
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, 45 * scale, -Math.PI / 2, -Math.PI / 2 + progress * Math.PI * 2);
                ctx.stroke();
            }
        }
    }

    // 传送阵
    if (gameState.teleports) {
        for (const tp of gameState.teleports) {
            const pos = worldToScreen(tp.x, tp.y);
            ctx.fillStyle = 'rgba(100, 200, 255, 0.3)';
            ctx.beginPath(); ctx.arc(pos.x, pos.y, 25 * scale, 0, Math.PI * 2); ctx.fill();
            ctx.strokeStyle = 'rgba(100, 200, 255, 0.6)';
            ctx.lineWidth = 2;
            ctx.beginPath(); ctx.arc(pos.x, pos.y, 25 * scale, 0, Math.PI * 2); ctx.stroke();
        }
    }

    // 防御塔攻击范围可视化
    const me = getMyHero();
    if (me && !me.dead) {
        for (const t of gameState.towers || []) {
            if (t.dead) continue;
            const d = Math.hypot(me.x - t.x, me.y - t.y);
            const range = t.attackRange || 500;
            const warnRange = range * 1.5;
            if (d > warnRange * 2) continue;
            const pos = worldToScreen(t.x, t.y);
            const r = range * scale;
            const isEnemy = t.team !== myTeam;
            const inRange = d <= range;
            if (isEnemy) {
                // 敌方塔：红色圈
                const alpha = inRange ? 0.3 : 0.1;
                ctx.fillStyle = `rgba(255, 50, 50, ${alpha})`;
                ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.fill();
                const pulse = inRange ? (Math.sin(Date.now() * 0.006) + 1) * 0.3 + 0.4 : 0.5;
                ctx.strokeStyle = `rgba(255, 80, 80, ${pulse})`;
                ctx.lineWidth = inRange ? 3 : 2;
                ctx.setLineDash([8, 4]);
                ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.stroke();
                ctx.setLineDash([]);
            } else {
                // 我方塔：淡蓝色圈
                ctx.fillStyle = `rgba(80, 180, 255, 0.06)`;
                ctx.beginPath(); ctx.arc(pos.x, pos.y, r, 0, Math.PI * 2); ctx.fill();
            }
        }
    }

    // 弹道
    for (const p of gameState.projectiles || []) {
        if (p.dead) continue;
        if (p.type === 'q_penetrate') {
            // 穿云箭：细长穿透箭矢
            const pos = worldToScreen(p.x, p.y);
            ctx.save();
            ctx.translate(pos.x, pos.y);
            ctx.rotate(Date.now() * 0.003);
            ctx.fillStyle = '#88ccff';
            ctx.fillRect(-18 * scale, -2 * scale, 36 * scale, 4 * scale);
            ctx.strokeStyle = '#fff';
            ctx.lineWidth = 1;
            ctx.strokeRect(-18 * scale, -2 * scale, 36 * scale, 4 * scale);
            ctx.restore();
        } else if (p.type === 'q') {
            // 灵符飞掷：旋转符咒
            const pos = worldToScreen(p.x, p.y);
            ctx.save();
            ctx.translate(pos.x, pos.y);
            ctx.rotate(Date.now() * 0.01);
            ctx.fillStyle = '#cc80ff';
            ctx.fillRect(-10 * scale, -10 * scale, 20 * scale, 20 * scale);
            ctx.strokeStyle = '#fff';
            ctx.lineWidth = 1.5;
            ctx.strokeRect(-10 * scale, -10 * scale, 20 * scale, 20 * scale);
            ctx.restore();
        } else {
            const color = p.type === 'tower' ? '#ffdd44' : '#fff';
            drawCircle(p.x, p.y, p.radius || 18, color, '#000');
        }
    }

    // 鼠标位置标记
    const mouseWorld = getMouseWorld();
    if (mouseWorld.x >= 0 && mouseWorld.x <= MAP_W && mouseWorld.y >= 0 && mouseWorld.y <= MAP_H) {
        const pos = worldToScreen(mouseWorld.x, mouseWorld.y);
        ctx.strokeStyle = 'rgba(255,255,255,0.6)';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(pos.x, pos.y, 12, 0, Math.PI * 2);
        ctx.stroke();
    }

    const frozen = hitStopTimer > 0;

    // 绘制飘字伤害数字（顿帧时不推进动画）
    for (let i = damageNumbers.length - 1; i >= 0; i--) {
        const dn = damageNumbers[i];
        const pos = worldToScreen(dn.x, dn.y);
        ctx.font = dn.isCrit ? 'bold 22px Microsoft YaHei' : '16px Microsoft YaHei';
        ctx.fillStyle = dn.isCrit ? '#ffd700' : '#fff';
        ctx.strokeStyle = '#000';
        ctx.lineWidth = 3;
        const text = '-' + dn.amount;
        ctx.strokeText(text, pos.x, pos.y);
        ctx.fillText(text, pos.x, pos.y);
        if (!frozen) {
            dn.y += dn.vy * (1 / 60);
            dn.vy += 60 * (1 / 60); // 重力加速度
            dn.life -= 1 / 60;
            if (dn.life <= 0) damageNumbers.splice(i, 1);
        }
    }

    if (frozen) {
        hitStopTimer -= 1 / 60;
    } else {
        // 顿帧结束，应用被暂存的状态
        if (pendingState) {
            gameState = pendingState;
            pendingState = null;
        }
        // 屏幕震动衰减
        if (shakeTimer > 0) {
            shakeTimer -= 1 / 60;
            if (shakeTimer <= 0) shakeIntensity = 0;
        }
        sendWASDMove();
        updateHUD();
    }
    renderMinimap();
    requestAnimationFrame(render);
}

function updateHUD() {
    if (!gameState || myHeroId === null) return;
    const me = getMyHero();
    if (!me) return;
    const names = { warrior: '狂战士', mage: '奥术师', archer: '神射手' };
    document.getElementById('heroName').textContent = names[me.role] || me.role;

    // 死亡计时
    const deathEl = document.getElementById('deathTimer');
    if (me.dead) {
        deathEl.classList.remove('hidden');
        document.getElementById('respawnTime').textContent = Math.ceil(6 + me.level - me.respawnTimer);
    } else {
        deathEl.classList.add('hidden');
    }

    // 回城进度
    const recallEl = document.getElementById('recallBar');
    if (me.isRecalling) {
        recallEl.classList.remove('hidden');
        document.getElementById('recallTime').textContent = (me.recallDuration - me.recallTimer).toFixed(1);
    } else {
        recallEl.classList.add('hidden');
    }

    if (me.dead) return;
    document.getElementById('heroLevel').textContent = me.level;
    document.getElementById('kills').textContent = me.kills;
    document.getElementById('deaths').textContent = me.deaths;
    document.getElementById('gold').textContent = me.gold;

    const buffText = [];
    if (me.buffs.dragon > 0) buffText.push(`龙BUFF ${me.buffs.dragon.toFixed(0)}s`);
    if (me.buffs.baron > 0) buffText.push(`大龙 ${me.buffs.baron.toFixed(0)}s`);
    document.getElementById('buffs').textContent = buffText.join(' ');
    document.getElementById('hpBar').style.width = `${(me.hp / me.maxHp) * 100}%`;
    document.getElementById('mpBar').style.width = `${(me.mp / me.maxMp) * 100}%`;
    document.getElementById('xpBar').style.width = `${(me.xp / me.xpToLevel) * 100}%`;

    const minutes = Math.floor(gameState.t / 60);
    const seconds = Math.floor(gameState.t % 60);
    document.getElementById('gameTime').textContent = `${minutes}:${seconds.toString().padStart(2, '0')}`;

    for (const slot of ['q', 'w', 'e', 'r']) {
        const el = document.getElementById('skill' + slot.toUpperCase());
        const skill = me.skills[slot];
        const cdEl = el.querySelector('.cd');
        if (skill.locked) {
            el.classList.remove('ready');
            if (!cdEl) {
                const div = document.createElement('div');
                div.className = 'cd';
                el.appendChild(div);
            }
            el.querySelector('.cd').textContent = 'Lv3';
        } else if (skill.cd <= 0) {
            el.classList.add('ready');
            if (cdEl) cdEl.remove();
        } else {
            el.classList.remove('ready');
            if (!cdEl) {
                const div = document.createElement('div');
                div.className = 'cd';
                el.appendChild(div);
            }
            el.querySelector('.cd').textContent = skill.cd.toFixed(1);
        }
        // 更新技能名称和描述
        if (skill.name && skill.desc) {
            const nameEl = el.querySelector('.skill-name');
            const descEl = el.querySelector('.skill-desc');
            if (nameEl) nameEl.textContent = skill.name;
            if (descEl) descEl.textContent = skill.desc;
        }
    }

    // 更新 Dev 面板全局状态
    updateDevPanel();
}

function updateDevPanel() {
    if (!gameState) return;
    const minutes = Math.floor(gameState.t / 60);
    const seconds = Math.floor(gameState.t % 60);
    const bk = gameState.teamKills ? gameState.teamKills[0] : 0;
    const rk = gameState.teamKills ? gameState.teamKills[1] : 0;

    let dragonRespawn = '--', baronRespawn = '--';
    if (gameState.monsters) {
        const dragon = gameState.monsters.find(m => m.type === 'dragon');
        const baron = gameState.monsters.find(m => m.type === 'baron');
        if (dragon && dragon.dead) dragonRespawn = dragon.respawnIn.toFixed(0) + 's';
        if (baron && baron.dead) baronRespawn = baron.respawnIn.toFixed(0) + 's';
    }

    document.getElementById('devGlobal').innerHTML =
        `时间 ${minutes}:${seconds.toString().padStart(2, '0')}<br>` +
        `击杀 ${bk} : ${rk}<br>` +
        `小龙刷新 ${dragonRespawn}<br>` +
        `大龙刷新 ${baronRespawn}`;
}

function renderMinimap() {
    if (!gameState) return;
    const w = minimapCanvas.width;
    const h = minimapCanvas.height;
    const scaleX = w / MAP_W;
    const scaleY = h / MAP_H;

    minimapCtx.fillStyle = '#1a2a1a';
    minimapCtx.fillRect(0, 0, w, h);

    function drawDot(x, y, r, color) {
        minimapCtx.fillStyle = color;
        minimapCtx.beginPath();
        minimapCtx.arc(x * scaleX, y * scaleY, r, 0, Math.PI * 2);
        minimapCtx.fill();
    }

    // 道路
    if (mapData && mapData.roads) {
        minimapCtx.fillStyle = '#5a4a38';
        for (const r of mapData.roads) {
            minimapCtx.fillRect(r.x * scaleX, r.y * scaleY, r.w * scaleX, r.h * scaleY);
        }
    } else {
        minimapCtx.strokeStyle = '#5a4a38';
        minimapCtx.lineWidth = 4;
        minimapCtx.beginPath();
        minimapCtx.moveTo(0, 7000 * scaleY);
        minimapCtx.lineTo(w, 7000 * scaleY);
        minimapCtx.moveTo(0, 3000 * scaleY);
        minimapCtx.lineTo(w, 3000 * scaleY);
        minimapCtx.stroke();
    }
    // 草丛
    if (mapData && mapData.bushes) {
        minimapCtx.fillStyle = 'rgba(30, 100, 30, 0.6)';
        for (const b of mapData.bushes) {
            minimapCtx.fillRect(b.x * scaleX, b.y * scaleY, b.w * scaleX, b.h * scaleY);
        }
    }
    // 墙体
    if (mapData && mapData.walls) {
        minimapCtx.fillStyle = 'rgba(80, 80, 80, 0.85)';
        for (const w of mapData.walls) {
            minimapCtx.fillRect(w.x * scaleX, w.y * scaleY, w.w * scaleX, w.h * scaleY);
        }
    }

    // 防御塔
    for (const t of gameState.towers || []) {
        if (t.dead) continue;
        drawDot(t.x, t.y, 4, t.team === 0 ? '#3355ff' : '#ff3333');
    }
    // 野怪
    for (const m of gameState.monsters || []) {
        if (m.dead) continue;
        drawDot(m.x, m.y, 3, m.type === 'baron' ? '#aa00ff' : '#ffaa00');
    }
    // 小兵
    for (const m of gameState.minions || []) {
        if (m.dead) continue;
        drawDot(m.x, m.y, 2, m.team === 0 ? '#7799ff' : '#ff7777');
    }
    // 传送阵
    if (gameState.teleports) {
        for (const tp of gameState.teleports) {
            minimapCtx.fillStyle = 'rgba(100, 200, 255, 0.5)';
            minimapCtx.beginPath();
            minimapCtx.arc(tp.x * scaleX, tp.y * scaleY, 2.5, 0, Math.PI * 2);
            minimapCtx.fill();
        }
    }
    // 英雄
    for (const h of gameState.heroes || []) {
        if (h.dead) continue;
        const isMe = h.id === myHeroId;
        drawDot(h.x, h.y, isMe ? 4 : 3, isMe ? '#ffd700' : (h.team === 0 ? '#4488ff' : '#ff4444'));
    }

    // 摄像机视野框
    const me = getMyHero();
    if (me) {
        const halfW = (canvas.width / 2 / scale) * scaleX;
        const halfH = (canvas.height / 2 / scale) * scaleY;
        minimapCtx.strokeStyle = '#fff';
        minimapCtx.lineWidth = 1;
        minimapCtx.strokeRect(me.x * scaleX - halfW, me.y * scaleY - halfH, halfW * 2, halfH * 2);
    }
}

function renderEndStats(stats) {
    const tbody = document.querySelector('#statsTable tbody');
    tbody.innerHTML = '';
    const names = { warrior: '狂战士', mage: '奥术师', archer: '神射手' };
    for (const h of stats.heroes) {
        const row = document.createElement('tr');
        row.style.borderBottom = '1px solid #333';
        row.innerHTML =
            `<td style="padding:6px 4px; color:${h.team === 0 ? '#4af' : '#f55'}">${names[h.role] || h.role}</td>` +
            `<td style="padding:6px 4px;">${h.team === 0 ? '蓝方' : '红方'}</td>` +
            `<td style="padding:6px 4px;">${h.kills}/${h.deaths}/${h.assists}</td>` +
            `<td style="padding:6px 4px;">${h.level}</td>` +
            `<td style="padding:6px 4px;">${h.gold}</td>` +
            `<td style="padding:6px 4px;">${h.damageDealt}</td>` +
            `<td style="padding:6px 4px;">${h.damageTaken}</td>` +
            `<td style="padding:6px 4px;">${h.healing}</td>`;
        tbody.appendChild(row);
    }

    // 绘制经济曲线
    const chart = document.getElementById('goldChart');
    const cctx = chart.getContext('2d');
    cctx.clearRect(0, 0, chart.width, chart.height);
    if (!stats.goldHistory || stats.goldHistory.length < 2) return;

    const maxT = stats.goldHistory[stats.goldHistory.length - 1].t;
    const maxGold = Math.max(...stats.goldHistory.map(p => Math.max(p.blueGold, p.redGold)), 1);

    function drawLine(data, key, color) {
        cctx.strokeStyle = color;
        cctx.lineWidth = 2;
        cctx.beginPath();
        for (let i = 0; i < data.length; i++) {
            const x = (data[i].t / maxT) * chart.width;
            const y = chart.height - (data[i][key] / maxGold) * chart.height * 0.85 - 10;
            if (i === 0) cctx.moveTo(x, y);
            else cctx.lineTo(x, y);
        }
        cctx.stroke();
    }

    drawLine(stats.goldHistory, 'blueGold', '#4af');
    drawLine(stats.goldHistory, 'redGold', '#f55');

    // 图例
    cctx.fillStyle = '#4af';
    cctx.fillRect(10, 10, 20, 10);
    cctx.fillStyle = '#fff';
    cctx.fillText('蓝方', 35, 19);
    cctx.fillStyle = '#f55';
    cctx.fillRect(80, 10, 20, 10);
    cctx.fillStyle = '#fff';
    cctx.fillText('红方', 105, 19);
}

requestAnimationFrame(render);
