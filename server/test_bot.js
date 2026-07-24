// MOBA 3v3 机器人对战测试
// 模拟 6 个 AI 玩家进行完整对局，用于发现逻辑问题

const WebSocket = require('ws');

const roles = ['warrior', 'mage', 'archer', 'warrior', 'mage', 'archer'];
const bots = [];
let stateCount = 0;
let gameEnded = false;
let gameStarted = false;

function log(idx, msg) {
    console.log(`[BOT${idx + 1}] ${msg}`);
}

function createBot(idx) {
    const ws = new WebSocket('ws://localhost:8080');
    const bot = { ws, idx, hero: null, team: null, role: roles[idx], lastAction: 0 };
    bots.push(bot);

    ws.on('open', () => {
        setTimeout(() => {
            ws.send(JSON.stringify({ type: 'join', role: bot.role }));
        }, idx * 300);
    });

    ws.on('message', (msg) => {
        const data = JSON.parse(msg);
        if (data.type === 'joined') {
            bot.team = data.team;
            log(idx, `加入 队伍=${data.team} 英雄=${data.role}`);
        } else if (data.type === 'start') {
            gameStarted = true;
            log(idx, '对局开始');
        } else if (data.type === 'end') {
            gameEnded = true;
            log(idx, `对局结束 胜者=${data.winner}`);
        } else if (data.type === 'error') {
            log(idx, `错误: ${data.message}`);
        } else if (data.state !== undefined) {
            stateCount++;
            bot.state = data;
            if (bot.hero) {
                const h = data.heroes.find(hero => hero.id === bot.hero.id);
                if (h) bot.hero = h;
            } else {
                const me = data.heroes.find(hero => hero.team === bot.team && hero.role === bot.role);
                if (me) bot.hero = me;
            }
        }
    });

    ws.on('error', (e) => console.error(`[BOT${idx + 1}] 错误: ${e.message}`));
    ws.on('close', () => log(idx, '断开连接'));

    return bot;
}

function think(bot) {
    if (!bot.hero || bot.hero.dead || !bot.state || bot.state.state !== 'playing') return;

    const now = Date.now();
    if (now - bot.lastAction < 200) return;
    bot.lastAction = now;

    const me = bot.hero;
    const enemies = [...bot.state.heroes, ...bot.state.minions, ...bot.state.towers, ...bot.state.monsters]
        .filter(e => e.team !== me.team && !e.dead);

    // 找最近目标
    let target = null, minD = Infinity;
    for (const e of enemies) {
        const d = Math.hypot(e.x - me.x, e.y - me.y);
        if (d < minD) { minD = d; target = e; }
    }

    // 血量低回基地
    if (me.hp < me.maxHp * 0.25) {
        const baseX = me.team === 0 ? 300 : 5700;
        bot.ws.send(JSON.stringify({ type: 'move', x: baseX, y: 2000 }));
        return;
    }

    if (target) {
        // 朝目标移动
        const approachDist = me.attackRange * 0.8;
        if (minD > approachDist) {
            const angle = Math.atan2(target.y - me.y, target.x - me.x);
            const tx = me.x + Math.cos(angle) * 250;
            const ty = me.y + Math.sin(angle) * 250;
            bot.ws.send(JSON.stringify({ type: 'move', x: tx, y: ty }));
        }

        // 普攻
        if (minD <= me.attackRange + 50) {
            bot.ws.send(JSON.stringify({ type: 'attack', targetId: target.id }));
        }

        // 放技能
        for (const slot of ['q', 'w', 'e', 'r']) {
            const skill = me.skills[slot];
            if (skill && skill.cd <= 0 && !skill.locked && minD < skill.range + 100) {
                bot.ws.send(JSON.stringify({
                    type: 'skill',
                    slot,
                    x: target.x,
                    y: target.y,
                    targetId: target.id
                }));
                break;
            }
        }
    } else {
        // 没有目标就往敌方主堡推进
        const goalX = me.team === 0 ? 5700 : 300;
        bot.ws.send(JSON.stringify({ type: 'move', x: goalX, y: 2000 }));
    }
}

for (let i = 0; i < 6; i++) createBot(i);

const thinkInterval = setInterval(() => {
    for (const bot of bots) think(bot);
}, 200);

setInterval(() => {
    if (!gameStarted) return;
    const state = bots[0].state;
    if (!state) return;
    const me = state.heroes[0];
    if (me) {
        console.log(`\n[状态] 时间=${state.t.toFixed(1)}s 金币=${me.gold} 等级=${me.level} 经验=${me.xp}/${me.xpToLevel} 龙BUFF=${me.buffs.dragon.toFixed(0)}s 大龙=${me.buffs.baron.toFixed(0)}s`);
        console.log(`[状态] 存活英雄=${state.heroes.filter(h => !h.dead).length}/6 存活塔=${state.towers.filter(t => !t.dead).length} 小兵=${state.minions.length}`);
    }
}, 5000);

setTimeout(() => {
    clearInterval(thinkInterval);
    console.log(`\n==== 测试结束 ====`);
    console.log(`状态更新次数: ${stateCount}`);
    console.log(`对局是否结束: ${gameEnded}`);
    if (bots[0].state) {
        const s = bots[0].state;
        console.log(`最终时间: ${s.t.toFixed(1)}s`);
        console.log(`最终胜者: ${s.winner || '无'}`);
        console.log(`最终存活塔: ${s.towers.filter(t => !t.dead).length}`);
        for (const h of s.heroes) {
            console.log(`  ${h.role}(队${h.team}): 等级=${h.level} 金币=${h.gold} 击杀=${h.kills} 死亡=${h.deaths}`);
        }
    }
    for (const bot of bots) bot.ws.close();
    process.exit(0);
}, 120000);
