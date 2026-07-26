// MOBA 3v3 PC 端原型 - 服务端权威逻辑
// 核心机制：推塔胜利、经济成长、3级解锁大招、大小龙BUFF、简易草丛视野

const WebSocket = require('ws');
const http = require('http');
const fs = require('fs');
const path = require('path');

// 加载瓦片地图数据
const mapData = JSON.parse(fs.readFileSync(path.join(__dirname, 'map.json'), 'utf8'));

const TICK_RATE = 20;
const DT = 1 / TICK_RATE;
const MAP_WIDTH = 10000;
const MAP_HEIGHT = 10000;
const TEAM_BLUE = 0;
const TEAM_RED = 1;
const PLAYERS_PER_TEAM = 3;

const HERO_RADIUS = 35;
const MINION_RADIUS = 22;
const TOWER_RADIUS = 45;
const DRAGON_RADIUS = 60;
const BARON_RADIUS = 75;

const LANE_TOP_Y = 7000;
const LANE_BOT_Y = 3000;
const ULTIMATE_UNLOCK_LEVEL = 3;
const MAX_LEVEL = 12;
const SKILL_MAX_LEVEL = { Q: 4, W: 4, E: 4, R: 3 };

// 升级所需经验公式
function calcExpNeeded(level) {
    return 100 + (level - 1) * 150 + Math.max(0, level - 5) * 100;
}

// 追赶/领先经验修正
function getExpModifier(hero, game) {
    if (!game || !game.heroes) return 1.0;
    let totalLevel = 0, count = 0;
    for (const h of game.heroes) { if (!h.dead) { totalLevel += h.level; count++; } }
    if (count === 0) return 1.0;
    const avgLevel = totalLevel / count;
    const diff = avgLevel - hero.level;
    if (diff >= 4) return 1.6;
    if (diff >= 2) return 1.3;
    if (diff <= -2) return 0.8;
    return 1.0;
}

// 等级压制伤害倍率
function getLevelSuppressionMul(attacker, defender) {
    const diff = attacker.level - defender.level;
    if (diff >= 6) return 1.15;
    if (diff >= 4) return 1.10;
    if (diff >= 2) return 1.05;
    return 1.0;
}

function dist(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); }
function clamp(v, min, max) { return Math.max(min, Math.min(max, v)); }
function angleTo(from, to) { return Math.atan2(to.y - from.y, to.x - from.x); }

// 处理英雄移动：英雄互相推开 + 墙体滑动阻挡
function resolveMovement(self, newX, newY, game) {
    let x = newX, y = newY;
    const minD = HERO_RADIUS * 2;
    for (const h of game.heroes) {
        if (h === self || h.dead) continue;
        const d = Math.hypot(x - h.x, y - h.y);
        if (d < minD && d > 0.01) {
            const push = (minD - d) * 0.5;
            x += (x - h.x) / d * push;
            y += (y - h.y) / d * push;
        }
    }
    // 墙体滑动：分别尝试 X/Y 方向，允许贴墙移动
    if (game.isWall(x, y, HERO_RADIUS)) {
        if (!game.isWall(x, self.y, HERO_RADIUS)) {
            y = self.y;
        } else if (!game.isWall(self.x, y, HERO_RADIUS)) {
            x = self.x;
        } else {
            x = self.x;
            y = self.y;
        }
    }
    return {
        x: clamp(x, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS),
        y: clamp(y, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS)
    };
}

function serializeState(game) {
    const visibleHeroes = game.heroes.map(h => {
        const inBush = game.isInBush(h.x, h.y);
        return { h, inBush };
    });

    return JSON.stringify({
        t: game.time,
        state: game.state,
        winner: game.winner,
        bushes: game.bushes,
        teleports: mapData.teleports || [],
        heroes: game.heroes.map(h => ({
            id: h.id, team: h.team, role: h.role,
            x: Math.round(h.x), y: Math.round(h.y),
            hp: Math.round(h.hp), maxHp: Math.round(h.maxHp),
            mp: Math.round(h.mp), maxMp: Math.round(h.maxMp),
            level: h.level, xp: Math.round(h.xp), xpToLevel: h.xpToLevel,
            skillPoints: h.skillPoints,
            skillLevels: { Q: h.skillLevels.Q, W: h.skillLevels.W, E: h.skillLevels.E, R: h.skillLevels.R },
            ap: h.ap, pDef: h.pDef, mDef: h.mDef,
            faceAngle: Math.round(h.faceAngle * 100) / 100,
            dead: h.dead, respawnTimer: Math.round(h.respawnTimer * 10) / 10,
            kills: h.kills, deaths: h.deaths, gold: h.gold,
            isBot: !!h.isBot,
            isRecalling: h.isRecalling, recallTimer: Math.round(h.recallTimer * 10) / 10, recallDuration: h.recallDuration,
            attackRange: h.attackRange,
            channeling: h.channeling,
            ccImmune: h.ccImmuneTimer > 0,
            shield: Math.round(h.shield),
            armorReduced: h.armorReduced > 0,
            rooted: h.rooted,
            stealthTimer: Math.round(h.stealthTimer * 10) / 10,
            charging: h.charging,
            hitFlash: h.hitFlashTimer > 0,
            buffs: {
                dragon: h._dragonStacks || 0,
                baron: h.buffBaronTimer > 0 ? Math.round(h.buffBaronTimer * 10) / 10 : 0
            },
            skills: {
                q: { name: h.skillQ.name, desc: h.skillQ.desc, cd: Math.max(0, Math.round(h.skillQ.cd * 10) / 10), max: h.skillQ.maxCd, range: h.skillQ.range, level: h.skillLevels.Q, maxLevel: SKILL_MAX_LEVEL.Q, unlocked: h.skillQ.unlocked },
                w: { name: h.skillW.name, desc: h.skillW.desc, cd: Math.max(0, Math.round(h.skillW.cd * 10) / 10), max: h.skillW.maxCd, range: h.skillW.range, level: h.skillLevels.W, maxLevel: SKILL_MAX_LEVEL.W, unlocked: h.skillW.unlocked },
                e: { name: h.skillE.name, desc: h.skillE.desc, cd: Math.max(0, Math.round(h.skillE.cd * 10) / 10), max: h.skillE.maxCd, range: h.skillE.range, level: h.skillLevels.E, maxLevel: SKILL_MAX_LEVEL.E, unlocked: h.skillE.unlocked },
                r: { name: h.skillR.name, desc: h.skillR.desc, cd: Math.max(0, Math.round(h.skillR.cd * 10) / 10), max: h.skillR.maxCd, range: h.skillR.range, level: h.skillLevels.R, maxLevel: SKILL_MAX_LEVEL.R, unlocked: h.skillR.unlocked }
            }
        })),
        minions: game.minions.map(m => ({ id: m.id, team: m.team, lane: m.lane, minionType: m.minionType, x: Math.round(m.x), y: Math.round(m.y), hp: Math.round(m.hp), maxHp: Math.round(m.maxHp), dead: m.dead, hitFlash: m.hitFlashTimer > 0, berserk: m.berserk, frenzyBuffed: m.frenzyBuffed })),
        towers: game.towers.map(t => ({ id: t.id, team: t.team, tier: t.tier, isMain: t.isMain, x: Math.round(t.x), y: Math.round(t.y), hp: Math.round(t.hp), maxHp: Math.round(t.maxHp), dead: t.dead, hitFlash: t.hitFlashTimer > 0, shieldStacks: t.shieldStacks || 0, attackRange: t.attackRange })),
        monsters: game.monsters.map(m => ({
            id: m.id, type: m.type, campType: m.campType, x: Math.round(m.x), y: Math.round(m.y),
            hp: Math.round(m.hp), maxHp: Math.round(m.maxHp), dead: m.dead,
            hitFlash: m.hitFlashTimer > 0,
            respawnIn: m.dead ? Math.max(0, Math.round((m.refreshInterval - m.respawnTimer) * 10) / 10) : 0
        })),
        projectiles: game.projectiles.map(p => ({ id: p.id, team: p.team, type: p.type, x: Math.round(p.x), y: Math.round(p.y), radius: p.radius, dead: p.dead, penetrating: p.penetrating })),
        effects: game.effects.map(e => ({ id: e.id, type: e.type, x: Math.round(e.x), y: Math.round(e.y), radius: Math.round(e.radius), life: Math.round(e.life * 10) / 10, maxLife: Math.round(e.maxLife * 10) / 10 })),
        teamKills: {
            [TEAM_BLUE]: game.heroes.filter(h => h.team === TEAM_BLUE).reduce((s, h) => s + h.kills, 0),
            [TEAM_RED]: game.heroes.filter(h => h.team === TEAM_RED).reduce((s, h) => s + h.kills, 0)
        }
    });
}

class Entity {
    constructor(id, x, y, radius, team) {
        this.id = id; this.x = x; this.y = y; this.radius = radius; this.team = team;
        this.hp = 100; this.maxHp = 100; this.dead = false;
        this.attackDamage = 10; this.attackRange = 100; this.attackSpeed = 1; this.attackCd = 0;
        this.moveSpeed = 300; this.goldValue = 0; this.xpValue = 0;
        this.lastHitSource = null;
        this.stats = { damageDealt: 0, damageTaken: 0, healing: 0, assists: 0 };
        this.hitFlashTimer = 0;
    }
    takeDamage(amount, source, game) {
        if (this.dead) return;
        let dmg = amount;
        // 受击打断回城和传送
        if (this instanceof Hero && this.isRecalling) this.cancelRecall();
        if (this instanceof Hero && this.teleportTimer > 0) this.teleportTimer = 0;
        // 破甲增伤：目标被破甲时伤害×1.3
        if (this instanceof Hero && this.armorReduced > 0) dmg = Math.floor(dmg * 1.3);
        // 等级压制：攻击者等级高于目标时增伤
        if (source instanceof Hero && this instanceof Hero) {
            dmg = Math.floor(dmg * getLevelSuppressionMul(source, this));
        }
        // 护盾优先扣除
        if (this instanceof Hero && this.shield > 0) {
            if (dmg <= this.shield) { this.shield -= dmg; dmg = 0; }
            else { dmg -= this.shield; this.shield = 0; }
        }
        if (dmg <= 0) return;
        this.hp = Math.max(0, this.hp - dmg);
        this.stats.damageTaken += dmg;
        this.hitFlashTimer = 0.12; // 受击闪白 0.12 秒
        // 野怪仇恨：记录攻击者的威胁值（伤害量）
        if (this instanceof Monster && source instanceof Hero) {
            this.addThreat(source, dmg);
        }
        // 不动如山：实时吸血 30%
        if (this instanceof Hero && this.ccImmuneTimer > 0) {
            const healAmount = Math.floor(dmg * 0.3);
            this.hp = Math.min(this.maxHp, this.hp + healAmount);
            this.stats.healing += healAmount;
        }
        // 广播伤害数字
        if (game && game.broadcastDamageNumber) {
            game.broadcastDamageNumber(this.x, this.y - this.radius, dmg, this instanceof Hero && dmg > this.maxHp * 0.15);
        }
        if (source instanceof Hero) {
            source.stats.damageDealt += dmg;
            if (!this.dead) this.lastHitSource = source;
        }
        if (this.hp <= 0) {
            this.dead = true;
            if (this instanceof Hero) this.deathStreak = (this.deathStreak || 0) + 1;
            // 死亡音效
            if (game && game.broadcastSound) {
                if (this instanceof Hero) game.broadcastSound('kill', this.x, this.y);
                else if (this instanceof Tower) game.broadcastSound('tower_destroy', this.x, this.y);
                else if (this instanceof Monster) game.broadcastSound('monster_kill', this.x, this.y, { type: this.type });
            }
            if (this.onDeath) this.onDeath(source, game);
            if (source && source.gainReward) source.gainReward(this, game);
            else if (this.lastHitSource && this.lastHitSource.gainReward) this.lastHitSource.gainReward(this, game);
            // 助攻统计：击杀者附近敌方英雄获得助攻
            if (this instanceof Hero && source instanceof Hero) {
                for (const h of game.heroes) {
                    if (h.team === source.team && h !== source && !h.dead && dist(h, this) < 1500) {
                        h.stats.assists++;
                    }
                }
                // 击杀狂怒：接下来 2 波兵获得 buff
                if (game._frenzyWavesLeft !== undefined) {
                    game._frenzyWavesLeft = Math.max(game._frenzyWavesLeft, 2);
                }
            }
            // 小兵自然死亡（漏刀）：附近敌方英雄获得 40% 保底金币
            if (this instanceof Minion && !(source instanceof Hero)) {
                this.grantGoldToNearby(game);
            }
            // 炮车狂暴爆炸：对附近敌方塔造成真实伤害
            if (this instanceof Minion && this.minionType === 'cannon' && this.berserk) {
                for (const t of game.towers) {
                    if (t.dead || t.team === this.team) continue;
                    if (dist(this, t) < 200) {
                        t.hp = Math.max(0, t.hp - 300); // 300 真实伤害
                        if (t.hp <= 0) t.dead = true;
                    }
                }
            }
            // 击杀屏幕震动
            if (game && game.broadcastShake) game.broadcastShake(8, 0.2);
        }
    }
    updateHitFlash(dt) {
        if (this.hitFlashTimer > 0) this.hitFlashTimer -= dt;
    }
    isEnemy(other) { return other.team !== this.team && !other.dead; }
    findTarget(range, game) {
        let best = null, bestScore = -Infinity;
        const candidates = [...game.heroes, ...game.minions, ...game.towers, ...game.monsters].filter(e => this.isEnemy(e));
        for (const e of candidates) {
            const d = dist(this, e);
            if (d > range) continue;
            let score = 0;
            if (e instanceof Hero) score += 300;
            else if (e instanceof Tower) score += 200;
            else if (e instanceof Monster) score += 100;
            else score += 50;
            score -= d * 0.1;
            if (score > bestScore) { bestScore = score; best = e; }
        }
        return best;
    }
}

class Hero extends Entity {
    constructor(id, x, y, team, role) {
        super(id, x, y, HERO_RADIUS, team);
        this.role = role; this.level = 1; this.xp = 0; this.xpToLevel = calcExpNeeded(1); this.gold = 0;
        this.kills = 0; this.deaths = 0; this.deathStreak = 0;
        this.faceAngle = team === TEAM_BLUE ? 0 : Math.PI;
        this.respawnTimer = 0; this.moveTarget = null;
        this.stunTimer = 0; this.shield = 0;
        this.buffDragonTimer = 0; // 小龙BUFF：攻击力加成
        this.buffBaronTimer = 0;  // 大龙BUFF：对塔伤害加成 + 金币加成
        this.goldIncomeTimer = 0;
        this.isRecalling = false;
        this.recallTimer = 0;
        this.recallDuration = 7; // 回城引导 7 秒
        this.teleportTimer = 0;        // 传送阵引导计时
        this.teleportPad = null;       // 当前传送阵
        this.teleportCd = 0;           // 传送冷却
        this.globalTpCd = 0;           // 全球传送冷却（3级解锁）
        this.globalTpTarget = null;    // 全球传送目标
        this.globalTpTimer = 0;        // 全球传送引导计时
        this.isGlobalTping = false;    // 正在全球传送
        this.ccImmuneTimer = 0;         // 免控计时（狂战士 R）
        this.damageTakenToHeal = 0;     // 不动如山期间累计受伤
        this.channelTimer = 0;          // 引导计时（神射手 R）
        this.channeling = false;        // 是否正在引导
        this.vortexTarget = null;       // 万象天引中心点
        this.vortexTimer = 0;           // 万象天引拉扯计时
        // v2 新增状态
        this.armorBreakReady = false;   // 狂战士 Q 命中后下次普攻破甲
        this.armorReduced = 0;          // 被破甲计时（防御降低30%）
        this.slowTimer = 0;             // 减速计时
        this.slowFactor = 1;            // 减速因子（默认1=无减速）
        this.rooted = false;            // 定身
        this.rootTimer = 0;             // 定身计时
        this.stealthTimer = 0;          // 隐匿计时（神射手 W）
        this.charging = false;          // 蓄力中（神射手 Q）
        this.chargeTimer = 0;           // 蓄力计时
        this.stillTimer = 0;            // 静止计时（草丛完全隐身）

        // 战后统计
        this.stats = { damageDealt: 0, damageTaken: 0, healing: 0, assists: 0 };

        // 等级系统 - 技能加点
        this.skillPoints = 0;
        this.skillLevels = { Q: 0, W: 0, E: 0, R: 0 };

        // 新基础属性（1级）— 按角色差异化
        const baseConfigs = {
            warrior: { name: '狂战士', hp: 800, mp: 300, ad: 60, ap: 20, pDef: 40, mDef: 30, range: 120, speed: 0.8, ms: 360, hpRegen: 25, mpRegen: 5 },
            mage:    { name: '奥术师', hp: 550, mp: 450, ad: 45, ap: 70, pDef: 20, mDef: 25, range: 450, speed: 0.7, ms: 350, hpRegen: 18, mpRegen: 8 },
            archer:  { name: '神射手', hp: 600, mp: 320, ad: 65, ap: 15, pDef: 25, mDef: 22, range: 550, speed: 0.9, ms: 340, hpRegen: 20, mpRegen: 6 }
        };
        // 每级成长
        const growthConfigs = {
            warrior: { hp: 180, mp: 30, ad: 12, ap: 4, pDef: 10, mDef: 8, hpRegen: 3, mpRegen: 1 },
            mage:    { hp: 120, mp: 60, ad: 6,  ap: 16, pDef: 5,  mDef: 6, hpRegen: 2, mpRegen: 3 },
            archer:  { hp: 130, mp: 35, ad: 14, ap: 3,  pDef: 6,  mDef: 5, hpRegen: 2, mpRegen: 1.5 }
        };

        const cfg = baseConfigs[role] || baseConfigs.warrior;
        const grow = growthConfigs[role] || growthConfigs.warrior;
        this.heroName = cfg.name;
        this.maxHp = cfg.hp; this.hp = cfg.hp;
        this.maxMp = cfg.mp; this.mp = cfg.mp;
        this.attackDamage = cfg.ad; this.ap = cfg.ap;
        this.pDef = cfg.pDef; this.mDef = cfg.mDef;
        this.attackRange = cfg.range; this.attackSpeed = cfg.speed; this.moveSpeed = cfg.ms;
        this.hpRegen = cfg.hpRegen; this.mpRegen = cfg.mpRegen;
        this.growth = grow;

        // 技能配置：按角色差异化 — 增加 baseDamage 和 damagePerLevel
        const skillConfigs = {
            warrior: {
                q: { name: '破阵突刺', desc: '冲刺+破甲：命中英雄后下次普攻降防30%', cd: 0, maxCd: 6, range: 450, baseDamage: 120, dmgPerLv: 30, mpCost: 25 },
                w: { name: '战意怒吼', desc: '范围伤害+减速30%+自身10%护盾', cd: 0, maxCd: 9, range: 300, baseDamage: 100, dmgPerLv: 25, mpCost: 35 },
                e: { name: '闪避突进', desc: '向鼠标方向快速位移', cd: 0, maxCd: 10, range: 400, baseDamage: 0, dmgPerLv: 0, mpCost: 25 },
                r: { name: '不动如山', desc: '3秒霸体，受击30%吸血', cd: 0, maxCd: 35, range: 0, baseDamage: 0, dmgPerLv: 0, mpCost: 80 }
            },
            mage: {
                q: { name: '灵符飞掷', desc: '发射符咒，击杀返还50%蓝+刷新', cd: 0, maxCd: 5, range: 600, baseDamage: 130, dmgPerLv: 30, mpCost: 25 },
                w: { name: '缚灵法阵', desc: '0.5秒延迟，伤害+定身1秒', cd: 0, maxCd: 8, range: 700, baseDamage: 110, dmgPerLv: 30, mpCost: 40 },
                e: { name: '闪避突进', desc: '向鼠标方向快速位移', cd: 0, maxCd: 10, range: 400, baseDamage: 0, dmgPerLv: 0, mpCost: 25 },
                r: { name: '万象天引', desc: '引导1秒后牵引敌人+爆发伤害', cd: 0, maxCd: 40, range: 450, baseDamage: 150, dmgPerLv: 55, mpCost: 90 }
            },
            archer: {
                q: { name: '穿云箭', desc: '蓄力0.5秒，穿透衰减(100%/80%/60%)', cd: 0, maxCd: 5, range: 800, baseDamage: 110, dmgPerLv: 25, mpCost: 25 },
                w: { name: '后撤步', desc: '后跳+1秒隐匿：+30%移速免小兵仇恨', cd: 0, maxCd: 7, range: 300, baseDamage: 0, dmgPerLv: 0, mpCost: 30 },
                e: { name: '闪避突进', desc: '向鼠标方向快速位移', cd: 0, maxCd: 10, range: 400, baseDamage: 0, dmgPerLv: 0, mpCost: 25 },
                r: { name: '万箭齐发', desc: '引导3秒扇形持续射击，可手动取消', cd: 0, maxCd: 30, range: 450, baseDamage: 35, dmgPerLv: 10, mpCost: 80 }
            }
        };
        const sc = skillConfigs[role] || skillConfigs.warrior;
        this.skillQ = Object.assign({}, sc.q); this.skillQ.damage = sc.q.baseDamage; this.skillQ.maxLevel = SKILL_MAX_LEVEL.Q; this.skillQ.unlocked = true;
        this.skillW = Object.assign({}, sc.w); this.skillW.damage = sc.w.baseDamage; this.skillW.maxLevel = SKILL_MAX_LEVEL.W; this.skillW.unlocked = false;
        this.skillE = Object.assign({}, sc.e); this.skillE.damage = sc.e.baseDamage; this.skillE.maxLevel = SKILL_MAX_LEVEL.E; this.skillE.unlocked = false;
        this.skillR = Object.assign({}, sc.r); this.skillR.damage = sc.r.baseDamage; this.skillR.maxLevel = SKILL_MAX_LEVEL.R; this.skillR.unlocked = false;
    }

    gainReward(target, game) {
        if (this.level >= MAX_LEVEL) return; // 满级不获取经验
        let gold = target.goldValue || 0;
        let xp = target.xpValue || 0;

        // 大龙BUFF：金币+30%
        if (this.buffBaronTimer > 0) gold = Math.floor(gold * 1.3);

        // 炮车赏金：存活超过 60 秒额外 +50 金币
        if (target instanceof Minion && target.minionType === 'cannon' && target.surviveTimer > 60) {
            gold += 50;
        }

        // === 经验值来源细分 ===
        if (target instanceof Minion) {
            gold = Math.floor(gold * 1.3); // 补刀加成 +30%
            // 新经验值：近战 40/炮车 60, 补刀者 100%, 附近友军 50%
            let baseXp = 40;
            if (target.minionType === 'cannon') baseXp = 60;
            else if (target.isSuper) baseXp = 50;
            xp = baseXp; // 补刀者 100%
            for (const h of game.heroes) {
                if (h.team === this.team && h !== this && !h.dead && dist(h, target) < 800) {
                    h.gold += Math.floor(gold * 0.5);
                    h._pendingXp = (h._pendingXp || 0) + Math.floor(baseXp * 0.5);
                }
            }
        } else if (target instanceof Monster) {
            // 野怪经验
            let baseXp = target.xpValue || 35;
            xp = baseXp;
            for (const h of game.heroes) {
                if (h.team === this.team && h !== this && !h.dead && dist(h, target) < 800) {
                    h._pendingXp = (h._pendingXp || 0) + Math.floor(baseXp * 0.5);
                }
            }
            // Boss 全队共享
            if (target.type === 'dragon' || target.type === 'baron') {
                const bossXp = target.type === 'dragon' ? 50 : 67;
                for (const h of game.heroes) {
                    if (h.team === this.team && !h.dead) {
                        h._pendingXp = (h._pendingXp || 0) + bossXp;
                    }
                }
            }
        } else if (target instanceof Hero) {
            // 击杀英雄：100 + 等级×20
            const base = 100 + target.level * 20;
            xp = Math.floor(base * 0.7); // 击杀者 70%
            const assistXp = Math.floor(base * 0.3); // 助攻者均分
            let assistants = [];
            for (const h of game.heroes) {
                if (h.team === this.team && h !== this && !h.dead && dist(h, target) < 1500) {
                    assistants.push(h);
                }
            }
            if (assistants.length > 0) {
                const each = Math.floor(assistXp / assistants.length);
                for (const h of assistants) {
                    h.gold += 80; h._pendingXp = (h._pendingXp || 0) + each;
                }
            } else {
                xp = base; // 无助攻，击杀者 100%
            }
            this.kills++; target.deaths++; this.deathStreak = 0;
        } else if (target instanceof Tower) {
            // 推塔经验：全队共享
            let towerXp = target.tier === 'inner' ? 120 : (target.tier === 'crystal' ? 0 : 80);
            xp = Math.floor(towerXp * 1.3); // 最后一击 +30%
            for (const h of game.heroes) {
                if (h.team === this.team && h !== this && !h.dead) {
                    h._pendingXp = (h._pendingXp || 0) + towerXp;
                }
            }
        }

        // 连续死亡惩罚（经验获取递减）
        if (target instanceof Hero) {
            const penalty = Math.max(0.4, 1.0 - target.deathStreak * 0.2);
            xp = Math.floor(xp * penalty);
        }

        // 经验追赶/领先修正
        const modifier = getExpModifier(this, game);
        xp = Math.floor(xp * modifier);

        this.gold += gold;
        this.xp += xp;
        while (this.xp >= this.xpToLevel && this.level < MAX_LEVEL) this.levelUp(game);
    }

    levelUp(game) {
        this.xp -= this.xpToLevel;
        this.level++;
        this.skillPoints++;
        if (this.level < MAX_LEVEL) {
            this.xpToLevel = calcExpNeeded(this.level);
        } else {
            this.xp = 0; this.xpToLevel = 0;
        }

        // 属性成长
        const g = this.growth;
        this.maxHp += g.hp; this.hp = Math.min(this.hp + g.hp, this.maxHp);
        this.maxMp += g.mp; this.mp = Math.min(this.mp + g.mp, this.maxMp);
        this.attackDamage += g.ad; this.ap += g.ap;
        this.pDef += g.pDef; this.mDef += g.mDef;
        this.hpRegen += g.hpRegen; this.mpRegen += g.mpRegen;

        // 自动解锁技能
        if (this.level >= 2 && !this.skillW.unlocked) { this.skillW.unlocked = true; this.skillLevels.W = 1; this.skillPoints--; this.skillW.damage = this.skillW.baseDamage + this.skillW.dmgPerLv; }
        if (this.level >= 3) {
            if (!this.skillE.unlocked) { this.skillE.unlocked = true; this.skillLevels.E = 1; this.skillPoints--; this.skillE.damage = this.skillE.baseDamage + this.skillE.dmgPerLv; }
            if (!this.skillR.unlocked) { this.skillR.unlocked = true; this.skillLevels.R = 1; this.skillPoints--; this.skillR.damage = this.skillR.baseDamage + this.skillR.dmgPerLv; }
        }

        // 广播升级事件
        if (game && game.broadcast) {
            game.broadcast({ type: 'level_up', heroId: this.id, level: this.level, skillPoints: this.skillPoints, team: this.team });
        }
    }

    upgradeSkill(slot) {
        if (this.skillPoints <= 0) return false;
        const s = slot.toUpperCase();
        const skill = this['skill' + s];
        if (!skill || !skill.unlocked) return false;
        if (this.skillLevels[s] >= SKILL_MAX_LEVEL[s]) return false;
        this.skillPoints--;
        this.skillLevels[s]++;
        skill.damage = skill.baseDamage + this.skillLevels[s] * skill.dmgPerLv;
        return true;
    }

    update(dt, game) {
        if (this.dead) {
            this.respawnTimer += dt;
            // 复活时间随等级增加：基础 6 秒 + 每级 1 秒
            const respawnTime = 6 + this.level;
            if (this.respawnTimer >= respawnTime) {
                this.dead = false; this.hp = this.maxHp; this.mp = this.maxMp; this.respawnTimer = 0;
                // 在泉水复活
                const fountain = game.getFountain(this.team);
                this.x = fountain.x; this.y = fountain.y;
                this.isRecalling = false; this.recallTimer = 0;
            }
            return;
        }

        // 泉水快速回血回蓝
        const fountain = game.getFountain(this.team);
        if (dist(this, fountain) < 250) {
            const heal = this.maxHp * 0.20 * dt;
            this.hp = Math.min(this.maxHp, this.hp + heal);
            this.stats.healing += heal;
            this.mp = Math.min(this.maxMp, this.mp + this.maxMp * 0.20 * dt);
        }

        // 回城引导
        if (this.isRecalling) {
            this.recallTimer += dt;
            if (this.recallTimer >= this.recallDuration) {
                this.hp = this.maxHp; this.mp = this.maxMp;
                this.x = fountain.x; this.y = fountain.y;
                this.isRecalling = false; this.recallTimer = 0;
            }
        }

        // 传送阵：站立 3 秒传送
        if (this.teleportCd > 0) this.teleportCd -= dt;
        if (!this.isRecalling && !this.channeling && !this.charging) {
            const tps = mapData.teleports || [];
            let onPad = null;
            for (const tp of tps) {
                if (dist(this, tp) < 80) { onPad = tp; break; }
            }
            if (onPad && this.moveTarget === null && this.teleportCd <= 0) {
                this.teleportTimer += dt;
                if (this.teleportTimer >= 3) {
                    // 传送到对角
                    const dest = tps.find(t => t.id === onPad.target);
                    if (dest) {
                        this.x = dest.x; this.y = dest.y;
                        this.teleportCd = 90;
                        this.stealthTimer = Math.max(this.stealthTimer, 0.3); // 落地加速由隐匿系统处理
                        // 传送后 30% 移速 buff 3 秒
                        // (用已有的 slowFactor/stealthTimer 扩展)
                    }
                    this.teleportTimer = 0;
                    this.teleportPad = null;
                }
            } else {
                this.teleportTimer = 0;
                this.teleportPad = null;
            }
        }

        // 全球传送引导
        if (this.globalTpCd > 0) this.globalTpCd -= dt;
        if (this.isGlobalTping && this.level >= 3) {
            // 被控打断
            if (this.stunTimer > 0) { this.isGlobalTping = false; this.globalTpTimer = 0; }
            else {
                this.globalTpTimer += dt;
                if (this.globalTpTimer >= 4) {
                    if (this.globalTpTarget) {
                        this.x = this.globalTpTarget.x;
                        this.y = this.globalTpTarget.y;
                        // 落地 40% 移速衰减 2 秒（用 slowFactor 负向实现）
                        this.slowTimer = 2; this.slowFactor = 0.6;
                    }
                    this.isGlobalTping = false;
                    this.globalTpTimer = 0;
                    this.globalTpCd = 120;
                }
            }
        }

        if (this.stunTimer > 0) this.stunTimer -= dt;

        // 免控计时（狂战士 R 不动如山）— 改为实时吸血，已在 takeDamage 中处理
        if (this.ccImmuneTimer > 0) this.ccImmuneTimer -= dt;

        // 减速计时
        if (this.slowTimer > 0) { this.slowTimer -= dt; if (this.slowTimer <= 0) this.slowFactor = 1; }
        // 破甲计时
        if (this.armorReduced > 0) this.armorReduced -= dt;
        if (this.armorBreakReady && this.level < 1) this.armorBreakReady = false; // 保留标记
        // 定身计时
        if (this.rootTimer > 0) { this.rootTimer -= dt; if (this.rootTimer <= 0) this.rooted = false; }
        // 隐匿计时
        if (this.stealthTimer > 0) this.stealthTimer -= dt;

        // 蓄力计时（神射手 Q）
        if (this.charging) {
            this.chargeTimer -= dt;
            if (this.chargeTimer <= 0) {
                this.charging = false;
                // 蓄力完成，发射穿云箭
                this._firePenetratingArrow(game);
            }
        }

        // 引导计时（神射手 R 万箭齐发 + 奥术师 R 万象天引）
        if (this.channeling) {
            this.channelTimer -= dt;
            if (this.role === 'archer') {
                // 神射手 R：每 0.33 秒扇形伤害
                if (!this._channelTickAcc) this._channelTickAcc = 0;
                this._channelTickAcc += dt;
                if (this._channelTickAcc >= 0.33) {
                    this._channelTickAcc -= 0.33;
                    const skill = this.skillR;
                    const angle = this.channelAngle || this.faceAngle;
                    const coneHalfAngle = Math.PI / 6;
                    for (const e of [...game.heroes, ...game.minions, ...game.towers, ...game.monsters]) {
                        if (!this.isEnemy(e)) continue;
                        const d = dist(this, e);
                        if (d > skill.range) continue;
                        const eAngle = angleTo(this, e);
                        let diff = eAngle - angle;
                        while (diff > Math.PI) diff -= Math.PI * 2;
                        while (diff < -Math.PI) diff += Math.PI * 2;
                        if (Math.abs(diff) < coneHalfAngle) {
                            let dmg = skill.damage;
                            if (this._dragonStacks >= 3) dmg = Math.floor(dmg * 1.3);
                            e.takeDamage(dmg, this, game);
                        }
                    }
                }
            } else if (this.role === 'mage') {
                // 奥术师 R：引导 1 秒后触发万象天引
                if (this.channelTimer <= 0) {
                    this.channeling = false;
                    const skill = this.skillR;
                    const tx = this._mageR_targetX || this.x;
                    const ty = this._mageR_targetY || this.y;
                    const enemies = [...game.heroes, ...game.minions, ...game.towers, ...game.monsters].filter(e => this.isEnemy(e));
                    for (const e of enemies) {
                        if (dist({ x: tx, y: ty }, e) < skill.range) {
                            e.takeDamage(Math.floor((skill.damage)), this, game);
                        }
                    }
                    game.vortexEffects.push(new VortexEffect(game.nextId++, tx, ty, skill.range, 1.5, this));
                    game.addEffect('vortex', tx, ty, skill.range, 1.5);
                    game.broadcastSound('skill', tx, ty, { slot: 'r', role: this.role });
                }
            }
            // 引导结束条件
            if (this.channelTimer <= 0 || (this.stunTimer > 0 && this.ccImmuneTimer <= 0)) {
                this.channeling = false;
                this._channelTickAcc = 0;
            }
        }

        // 自然经济增长：每秒 5 金币
        this.goldIncomeTimer += dt;
        if (this.goldIncomeTimer >= 1) {
            this.gold += 5;
            this.goldIncomeTimer -= 1;
        }

        // BUFF 计时
        if (this.buffBaronTimer > 0) this.buffBaronTimer -= dt;
        // 龙魂层数：第1层 HP 回复 1%/2s
        if (this._dragonStacks >= 1) {
            this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.005 * dt);
        }

        this.mp = Math.min(this.maxMp, this.mp + this.mpRegen * dt);
        // 自然生命恢复
        this.hp = Math.min(this.maxHp, this.hp + this.hpRegen * dt);
        // 处理待处理的队友经验
        if (this._pendingXp && this._pendingXp > 0) {
            this.xp += this._pendingXp;
            delete this._pendingXp;
            while (this.xp >= this.xpToLevel && this.level < MAX_LEVEL) this.levelUp(game);
        }
        if (this.attackCd > 0) this.attackCd -= dt;
        ['Q', 'W', 'E', 'R'].forEach(s => { const sk = this['skill' + s]; if (sk.cd > 0) sk.cd -= dt; });

        // 静止计时：用于草丛完全隐身
        if (!this.moveTarget && !this.channeling && !this.charging && !this.isRecalling) {
            this.stillTimer += dt;
        } else {
            this.stillTimer = 0;
        }

        if (this.stunTimer <= 0 && !this.channeling && !this.rooted && this.moveTarget) {
            const d = dist(this, this.moveTarget);
            if (d < 10) this.moveTarget = null;
            else {
                this.cancelRecall();
                const angle = angleTo(this, this.moveTarget);
                this.faceAngle = angle;
                let ms = this.moveSpeed * this.slowFactor; // 减速效果
                if (this.stealthTimer > 0) ms *= 1.3;       // 隐匿加速
                if (this.buffBaronTimer > 0) ms *= 1.1;
                const newX = clamp(this.x + Math.cos(angle) * ms * dt, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
                const newY = clamp(this.y + Math.sin(angle) * ms * dt, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
                const resolved = resolveMovement(this, newX, newY, game);
                this.x = resolved.x;
                this.y = resolved.y;
            }
        }
    }

    cancelRecall() {
        if (this.isRecalling) {
            this.isRecalling = false;
            this.recallTimer = 0;
        }
    }

    startRecall() {
        if (this.dead || this.isRecalling) return false;
        this.isRecalling = true;
        this.recallTimer = 0;
        return true;
    }

    castSkill(slot, target, game) {
        if (this.dead || this.stunTimer > 0) return false;
        if (this.channeling || this.charging) return false;
        // 定身时不能放 E（位移）
        if (this.rooted && slot === 'e') return false;
        this.cancelRecall();
        const skill = this['skill' + slot.toUpperCase()];
        if (!skill || skill.cd > 0 || this.mp < skill.mpCost) return false;
        if (slot === 'r' && !this.skillR.unlocked) return false;

        let angle = this.faceAngle;
        let tx = this.x + Math.cos(angle) * 300;
        let ty = this.y + Math.sin(angle) * 300;
        if (target && target.x !== undefined) {
            angle = angleTo(this, target);
            tx = target.x; ty = target.y;
        }

        const enemies = [...game.heroes, ...game.minions, ...game.towers, ...game.monsters].filter(e => this.isEnemy(e));
        let damageMul = 1;
        if (this._dragonStacks >= 3) damageMul = 1.3;

        // ============ 狂战士 ============
        if (this.role === 'warrior') {
            if (slot === 'q') {
                // 破阵突刺：冲刺 + 矩形碰撞 + 破甲标记
                const dashAngle = angleTo(this, { x: tx, y: ty });
                const dashDist = 300;
                const newX = clamp(this.x + Math.cos(dashAngle) * dashDist, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
                const newY = clamp(this.y + Math.sin(dashAngle) * dashDist, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
                const resolved = resolveMovement(this, newX, newY, game);
                this.x = resolved.x;
                this.y = resolved.y;
                const rectHalfW = 80, rectLen = 250;
                const rectCenterX = this.x + Math.cos(dashAngle) * rectLen / 2;
                const rectCenterY = this.y + Math.sin(dashAngle) * rectLen / 2;
                let hitHero = false;
                for (const e of enemies) {
                    const dx = e.x - rectCenterX, dy = e.y - rectCenterY;
                    const localX = dx * Math.cos(-dashAngle) - dy * Math.sin(-dashAngle);
                    const localY = dx * Math.sin(-dashAngle) + dy * Math.cos(-dashAngle);
                    if (Math.abs(localX) < rectLen / 2 + e.radius && Math.abs(localY) < rectHalfW + e.radius) {
                        e.takeDamage(Math.floor(skill.damage * damageMul), this, game);
                        if (e instanceof Hero) hitHero = true;
                    }
                }
                if (hitHero) this.armorBreakReady = true; // 命中英雄后下次普攻破甲
                game.addEffect('warrior_q_dash', this.x, this.y, 40, 0.3);
                game.addEffect('warrior_q_dust', this.x, this.y, 60, 0.4);
            } else if (slot === 'w') {
                // 战意怒吼：AOE + 减速 + 护盾
                for (const e of enemies) {
                    if (dist(this, e) < skill.range) {
                        e.takeDamage(Math.floor(skill.damage * damageMul), this, game);
                        if (e instanceof Hero) { e.slowTimer = 2; e.slowFactor = 0.7; }
                    }
                }
                this.shield = Math.floor(this.maxHp * 0.1); // 10% 最大生命护盾
                game.addEffect('ring_expand', this.x, this.y, skill.range, 0.5);
                game.addEffect('shield_glow', this.x, this.y, HERO_RADIUS + 25, 4);
            } else if (slot === 'e') {
                const dashDist = Math.min(skill.range, dist(this, { x: tx, y: ty }));
                const dashAngle = dist(this, { x: tx, y: ty }) < 5 ? angle : angleTo(this, { x: tx, y: ty });
                const newX = clamp(this.x + Math.cos(dashAngle) * dashDist, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
                const newY = clamp(this.y + Math.sin(dashAngle) * dashDist, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
                const resolved = resolveMovement(this, newX, newY, game);
                this.x = resolved.x;
                this.y = resolved.y;
                game.addEffect('dash', this.x, this.y, HERO_RADIUS + 15, 0.3);
            } else if (slot === 'r') {
                this.ccImmuneTimer = 3;
                game.addEffect('shield_glow', this.x, this.y, HERO_RADIUS + 30, 3);
            }
        }

        // ============ 奥术师 ============
        else if (this.role === 'mage') {
            if (slot === 'q') {
                const proj = new Projectile(game.nextId++, this.x, this.y, null, this.team, 'q',
                    Math.floor(skill.damage * damageMul), Math.cos(angle) * 650, Math.sin(angle) * 650, 1.5, 25, this);
                proj.skillSlot = 'q'; // 标记技能槽，用于击杀刷新判断
                game.projectiles.push(proj);
                game.addEffect('mage_q_trail', this.x, this.y, 20, 0.15);
            } else if (slot === 'w') {
                // 缚灵法阵：延迟 AOE + 定身
                const de = new DelayedEffect(game.nextId++, tx, ty, skill.range, 0.5,
                    Math.floor(skill.damage * damageMul), this, game);
                de.rootTargets = true; // 标记需要定身
                game.delayedEffects.push(de);
            } else if (slot === 'e') {
                if (this.rooted) { this.mp = Math.min(this.maxMp, this.mp + skill.mpCost); return false; }
                const dashDist = Math.min(skill.range, dist(this, { x: tx, y: ty }));
                const dashAngle = dist(this, { x: tx, y: ty }) < 5 ? angle : angleTo(this, { x: tx, y: ty });
                const newX = clamp(this.x + Math.cos(dashAngle) * dashDist, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
                const newY = clamp(this.y + Math.sin(dashAngle) * dashDist, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
                const resolved = resolveMovement(this, newX, newY, game);
                this.x = resolved.x;
                this.y = resolved.y;
                game.addEffect('dash', this.x, this.y, HERO_RADIUS + 15, 0.3);
            } else if (slot === 'r') {
                // 万象天引：引导 1 秒后生效
                this.channeling = true;
                this.channelTimer = 1;
                this._mageR_targetX = tx;
                this._mageR_targetY = ty;
                game.addEffect('vortex', tx, ty, skill.range, 1.5);
            }
        }

        // ============ 神射手 ============
        else if (this.role === 'archer') {
            if (slot === 'q') {
                // 穿云箭：蓄力 0.5 秒后发射
                this.charging = true;
                this.chargeTimer = 0.5;
                this._chargeDamage = Math.floor(skill.damage * damageMul);
                this._chargeAngle = angle;
                game.addEffect('charge_indicator', this.x, this.y, HERO_RADIUS + 20, 0.5);
            } else if (slot === 'w') {
                // 后撤步：位移 + 隐匿
                const oldX = this.x, oldY = this.y;
                let backAngle = this.moveTarget
                    ? angleTo(this, this.moveTarget) + Math.PI
                    : this.faceAngle + Math.PI;
                const newX = clamp(this.x + Math.cos(backAngle) * 250, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
                const newY = clamp(this.y + Math.sin(backAngle) * 250, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
                const resolved = resolveMovement(this, newX, newY, game);
                this.x = resolved.x;
                this.y = resolved.y;
                this.stealthTimer = 1; // 1 秒隐匿
                game.addEffect('ghost_shadow', oldX, oldY, HERO_RADIUS, 0.25);
            } else if (slot === 'e') {
                const dashDist = Math.min(skill.range, dist(this, { x: tx, y: ty }));
                const dashAngle = dist(this, { x: tx, y: ty }) < 5 ? angle : angleTo(this, { x: tx, y: ty });
                const newX = clamp(this.x + Math.cos(dashAngle) * dashDist, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
                const newY = clamp(this.y + Math.sin(dashAngle) * dashDist, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
                const resolved = resolveMovement(this, newX, newY, game);
                this.x = resolved.x;
                this.y = resolved.y;
                game.addEffect('dash', this.x, this.y, HERO_RADIUS + 15, 0.3);
            } else if (slot === 'r') {
                // 万箭齐发：引导 3 秒，扇形持续伤害
                this.channeling = true;
                this.channelTimer = 3;
                this.channelAngle = angle;
                game.addEffect('arrow_rain', this.x, this.y, skill.range, 3);
            }
        }

        this.mp -= skill.mpCost;
        skill.cd = skill.maxCd;
        if (!(this.role === 'mage' && slot === 'w')) {
            game.broadcastSound('skill', this.x, this.y, { slot, role: this.role });
        }
        return true;
    }

    // 蓄力完成后发射穿云箭（神射手 Q）
    _firePenetratingArrow(game) {
        const dmg = this._chargeDamage;
        const angle = this._chargeAngle || this.faceAngle;
        const proj = new Projectile(game.nextId++, this.x, this.y, null, this.team, 'q_penetrate',
            dmg, Math.cos(angle) * 800, Math.sin(angle) * 800, 2.5, 18, this);
        proj.penetrating = true;
        proj.penetrationCount = 0;
        proj.baseDamage = dmg;
        game.projectiles.push(proj);
        game.broadcastSound('skill', this.x, this.y, { slot: 'q', role: this.role });
    }

    basicAttack(target, game) {
        if (this.dead || this.stunTimer > 0 || this.attackCd > 0) return false;
        this.cancelRecall();
        if (!target || target.dead || dist(this, target) > this.attackRange) return false;
        this.faceAngle = angleTo(this, target);

        // 如果普攻敌方英雄，触发附近敌方小兵仇恨
        if (target instanceof Hero) {
            // 破甲触发：狂战士 Q 命中后，下次普攻附加破甲
            if (this.armorBreakReady && this.role === 'warrior') {
                target.armorReduced = 3; // 3 秒破甲
                this.armorBreakReady = false;
                game.addEffect('armor_break', target.x, target.y, target.radius + 15, 3);
            }
            for (const m of game.minions) {
                // 隐匿英雄不触发小兵仇恨
                if (m.team === target.team && dist(m, target) < 500 && !m.dead && this.stealthTimer <= 0) {
                    m.setAggro(this);
                }
            }
        }
        let dmg = this.attackDamage;
        if (this._dragonStacks >= 3) dmg = Math.floor(dmg * 1.3);
        if (this._dragonStacks >= 2 && target instanceof Tower) dmg = Math.floor(dmg * 1.3);
        if (this.buffBaronTimer > 0 && target instanceof Tower) dmg = Math.floor(dmg * 1.5);

        if (this.role === 'mage' || this.role === 'archer') {
            game.projectiles.push(new Projectile(game.nextId++, this.x, this.y, target, this.team, 'auto', dmg, 0, 0, 99, 18, this));
        } else {
            game.broadcastSound('hit', target.x, target.y, { sourceRole: this.role });
            target.takeDamage(dmg, this, game);
        }
        this.attackCd = 1 / this.attackSpeed;
        return true;
    }
}

class Minion extends Entity {
    constructor(id, x, y, team, lane, type = 'melee', gameTime = 0, isSuper = false) {
        const isCannon = type === 'cannon';
        super(id, x, y, isCannon ? 28 : 22, team);
        this.lane = lane;
        this.minionType = type;
        this.isSuper = isSuper; // 超级兵（破二塔后）
        // 基础属性
        if (type === 'cannon') {
            this.baseHp = isSuper ? 1620 : 900; this.baseAtk = isSuper ? 195 : 130;
            this.attackSpeed = 0.5; this.moveSpeed = 220; this.attackRange = 450;
            this.goldValue = 120; this.xpValue = 55;
            this.surviveTimer = 0;
            this.berserk = false;
        } else {
            this.baseHp = 550; this.baseAtk = 45;
            this.attackSpeed = 1.0; this.moveSpeed = 240; this.attackRange = 120;
            this.goldValue = 65; this.xpValue = 30;
        }
        // 随时间成长（每3分钟+一次）
        const minutes = Math.floor(gameTime / 180);
        const growthLevels = Math.min(minutes, 10); // 30分钟封顶
        this.maxHp = this.baseHp + (type === 'cannon' ? 100 : 60) * growthLevels;
        this.hp = this.maxHp;
        this.attackDamage = this.baseAtk + (type === 'cannon' ? 18 : 8) * growthLevels;
        if (isSuper) { this.maxHp = Math.floor(this.maxHp * 1.8); this.hp = this.maxHp; this.attackDamage = Math.floor(this.attackDamage * 1.5); }
        // 护甲/魔抗（简化：对物理和魔法伤害统一减伤处理在 takeDamage 中）
        this.armor = type === 'cannon' ? 30 : 20;
        this.magicResist = type === 'cannon' ? 15 : 10;

        const targetY = lane === 'top' ? LANE_TOP_Y : LANE_BOT_Y;
        this.waypoints = team === TEAM_BLUE
            ? [{ x: MAP_WIDTH / 2, y: targetY }, { x: MAP_WIDTH - 350, y: targetY }]
            : [{ x: MAP_WIDTH / 2, y: targetY }, { x: 350, y: targetY }];
        this.waypointIndex = 0;
        this.aggroTarget = null;
        this.aggroTimer = 0;
        this.lastHitHero = null;
        this.frenzyBuffed = false;
        this.towerDamageBonus = type === 'cannon' ? (isSuper ? 2.0 : 1.8) : 1.1; // 对塔倍率
    }

    // 伤害倍率：根据目标类型
    getDamageMultiplier(target) {
        if (target instanceof Hero) return 1.0;
        if (target instanceof Minion) return this.minionType === 'cannon' ? 1.5 : 1.2;
        if (target instanceof Tower) return this.towerDamageBonus;
        return 1.0;
    }

    grantGoldToNearby(game) {
        for (const h of game.heroes) {
            if (h.dead || h.team !== this.team) continue;
            if (dist(h, this) < 800) {
                h.gold += Math.floor(this.goldValue * 0.5); // 自然死亡 50%
                h.xp += Math.floor(this.xpValue * 0.5);
            }
        }
    }

    setAggro(hero) {
        if (hero.stealthTimer > 0) return;
        this.aggroTarget = hero;
        this.aggroTimer = 3;
    }

    // 仇恨优先级：保护友方英雄 > 敌方小兵 > 敌方塔 > 敌方水晶 > 敌方英雄
    findPriorityTarget(game) {
        // 1. 正在攻击己方英雄的敌方英雄
        for (const h of game.heroes) {
            if (h.dead || h.team === this.team) continue;
            for (const ally of game.heroes) {
                if (ally.dead || ally.team !== this.team || ally === h) continue;
                if (dist(h, ally) < h.attackRange + 50 && dist(this, h) < 800) return h;
            }
        }
        // 2. 敌方小兵（大范围检测）
        let mTarget = this.findTarget(this.attackRange + 500, game);
        if (mTarget && mTarget instanceof Minion) return mTarget;
        // 3. 敌方塔
        for (const t of game.towers) {
            if (t.dead || t.team === this.team) continue;
            if (dist(this, t) < this.attackRange + 100) return t;
        }
        // 4. 按原 findTarget
        return this.findTarget(this.attackRange + 80, game) || mTarget;
    }

    update(dt, game) {
        if (this.dead) return;

        if (this.minionType === 'cannon') this.surviveTimer += dt;

        if (this.aggroTimer > 0) {
            this.aggroTimer -= dt;
            if (this.aggroTimer <= 0 || (this.aggroTarget && this.aggroTarget.dead)) {
                this.aggroTarget = null;
                this.aggroTimer = 0;
            }
        }

        // 炮车狂暴
        if (this.minionType === 'cannon' && !this.berserk) {
            let nearEnemyTower = false, hasAlliedMinion = false;
            for (const t of game.towers) {
                if (t.dead || t.team === this.team) continue;
                if (dist(this, t) < t.attackRange + 100) { nearEnemyTower = true; break; }
            }
            if (nearEnemyTower) {
                hasAlliedMinion = game.minions.some(m => m !== this && m.team === this.team && !m.dead && dist(this, m) < 600);
                if (!hasAlliedMinion) { this.berserk = true; this.attackSpeed *= 2; this.moveSpeed *= 1.5; }
            }
        }

        let target = null;
        if (this.aggroTarget && !this.aggroTarget.dead && dist(this, this.aggroTarget) < 800) {
            if (this.aggroTarget.stealthTimer > 0) { this.aggroTarget = null; this.aggroTimer = 0; }
            else target = this.aggroTarget;
        }
        if (!target) target = this.findPriorityTarget(game);
        if (target && target.stealthTimer > 0) target = null;

        if (target) {
            const d = dist(this, target);
            if (d <= this.attackRange) {
                if (this.attackCd <= 0) {
                    let dmg = Math.floor(this.attackDamage * this.getDamageMultiplier(target));
                    // 护甲减伤简化：每点护甲减0.5%
                    if (target instanceof Hero && target.armor) dmg = Math.floor(dmg * (1 - target.armor * 0.005));
                    if (this.frenzyBuffed) dmg = Math.floor(dmg * 1.5);
                    target.takeDamage(dmg, this, game);
                    this.attackCd = 1 / this.attackSpeed;
                }
            } else {
                let ms = this.moveSpeed;
                if (this.frenzyBuffed) ms *= 1.5;
                const angle = angleTo(this, target);
                this.x += Math.cos(angle) * ms * dt;
                this.y += Math.sin(angle) * ms * dt;
            }
        } else {
            const wp = this.waypoints[this.waypointIndex];
            if (wp) {
                const d = dist(this, wp);
                if (d < 30) this.waypointIndex++;
                else {
                    let ms = this.moveSpeed;
                    if (this.frenzyBuffed) ms *= 1.5;
                    const angle = angleTo(this, wp);
                    this.x += Math.cos(angle) * ms * dt;
                    this.y += Math.sin(angle) * ms * dt;
                }
            } else {
                // 路径走完：往敌方基地方向继续走
                const dir = this.team === TEAM_BLUE ? 1 : -1;
                let ms = this.moveSpeed;
                if (this.frenzyBuffed) ms *= 1.5;
                this.x += dir * ms * dt;
            }
        }
        if (this.attackCd > 0) this.attackCd -= dt;
        this.x = clamp(this.x, MINION_RADIUS, MAP_WIDTH - MINION_RADIUS);
        this.y = clamp(this.y, MINION_RADIUS, MAP_HEIGHT - MINION_RADIUS);
    }
}

class Tower extends Entity {
    constructor(id, x, y, team, tier = 'outer') {
        super(id, x, y, TOWER_RADIUS + (tier === 'crystal' ? 20 : 0), team);
        this.tier = tier;
        this.isMain = (tier === 'crystal');
        // 塔属性按等级
        if (tier === 'outer') {
            this.maxHp = 2500; this.hp = 2500;
            this.attackDamage = 180; this.baseDamage = 180;
            this.attackRange = 400; this.attackSpeed = 1.25; // 1/0.8
            this.stackPerHit = 0.2; this.maxStack = 2.0; // 最高 360
            this.goldValue = 150; this.xpValue = 80;
            this.minionMeleeMul = 1.5; this.minionCannonMul = 1.0;
        } else if (tier === 'inner') {
            this.maxHp = 3500; this.hp = 3500;
            this.attackDamage = 220; this.baseDamage = 220;
            this.attackRange = 450; this.attackSpeed = 1.25;
            this.stackPerHit = 0.25; this.maxStack = 2.5; // 最高 550
            this.goldValue = 200; this.xpValue = 100;
            this.slowAura = true; // 减速光环
            this.minionMeleeMul = 1.8; this.minionCannonMul = 1.2;
            // 护盾系统
            this.shieldStacks = 2; this.shieldPerStack = 800;
            this.shieldTimer = 0;
        } else if (tier === 'crystal') {
            this.maxHp = 6000; this.hp = 6000;
            this.attackDamage = 350; this.baseDamage = 350;
            this.attackRange = 800; this.attackSpeed = 1.25;
            this.stackPerHit = 0; this.maxStack = 0; // 水晶不递增
            this.goldValue = 400; this.xpValue = 200;
            this.execute = true; // 斩杀机制
        }
        this.lastTarget = null;  // 伤害递增用
        this.damageStack = 0;    // 当前递增层数
    }

    takeDamage(amount, source, game) {
        // 二塔护盾吸收
        if (this.tier === 'inner' && this.shieldStacks > 0) {
            const shieldHp = this.shieldStacks * this.shieldPerStack;
            if (amount <= shieldHp) {
                this.shieldStacks = Math.ceil((shieldHp - amount) / this.shieldPerStack);
                // 破盾奖励
                if (source instanceof Hero && Math.ceil((shieldHp - amount) / this.shieldPerStack) < Math.ceil(shieldHp / this.shieldPerStack)) {
                    source.gold += 30;
                }
                return;
            } else {
                this.shieldStacks = 0;
                if (source instanceof Hero) source.gold += 30;
                amount -= shieldHp;
            }
        }
        this.hp = Math.max(0, this.hp - amount);
        this.hitFlashTimer = 0.12;
        if (this.hp <= 0) {
            this.dead = true;
            if (game && game.broadcastSound) game.broadcastSound('tower_destroy', this.x, this.y);
            if (source && source.gainReward) source.gainReward(this, game);
            if (game && game.broadcastShake) game.broadcastShake(8, 0.2);
        }
    }

    findTowerTarget(game) {
        let best = null, bestScore = -Infinity;
        const candidates = [...game.heroes, ...game.minions].filter(e => this.isEnemy(e) && dist(this, e) <= this.attackRange);
        for (const e of candidates) {
            let score = 0;
            if (e instanceof Minion) score += 500;
            else if (e instanceof Hero) score += 100;
            score -= dist(this, e) * 0.1;
            if (score > bestScore) { bestScore = score; best = e; }
        }
        return best;
    }

    update(dt, game) {
        if (this.dead) return;

        // 二塔护盾充能
        if (this.tier === 'inner') {
            this.shieldTimer += dt;
            if (this.shieldTimer >= 60 && this.shieldStacks < 2) {
                this.shieldStacks++;
                this.shieldTimer = 0;
            }
        }

        // 二塔减速光环
        if (this.slowAura) {
            for (const h of game.heroes) {
                if (h.dead || h.team === this.team) continue;
                if (dist(this, h) < 500) { h.slowTimer = 0.2; h.slowFactor = 0.8; }
            }
        }

        const target = this.findTowerTarget(game);
        if (target && this.attackCd <= 0) {
            // 伤害递增：切换目标重置
            if (target !== this.lastTarget) { this.damageStack = 0; this.lastTarget = target; }
            let dmg = this.baseDamage;
            if (this.stackPerHit > 0) {
                dmg = Math.floor(this.baseDamage * (1 + this.damageStack * this.stackPerHit));
                this.damageStack++;
                if (this.damageStack > this.maxStack / this.stackPerHit) {
                    this.damageStack = this.maxStack / this.stackPerHit;
                }
            }
            // 对小兵伤害倍率
            if (target instanceof Minion) {
                dmg = Math.floor(dmg * (target.minionType === 'cannon' ? this.minionCannonMul : this.minionMeleeMul));
            }
            // 水晶斩杀
            if (this.execute && target instanceof Hero && target.hp < target.maxHp * 0.2) {
                const extraDmg = Math.floor(target.hp * 0.1);
                target.takeDamage(extraDmg, this, game);
            }
            game.projectiles.push(new Projectile(game.nextId++, this.x, this.y, target, this.team, 'tower', dmg, 0, 0, 99, 18));
            this.attackCd = 1 / this.attackSpeed;
        }
        if (this.attackCd > 0) this.attackCd -= dt;
    }
}

class Monster extends Entity {
    constructor(id, x, y, type, campType = null, unitIndex = 0) {
        const isBaron = type === 'baron';
        const isCamp = type === 'camp';
        const r = isCamp ? 25 : (isBaron ? BARON_RADIUS : DRAGON_RADIUS);
        super(id, x, y, r, -1);
        this.type = type;
        this.campType = campType;
        this.evolved = false;
        // 野怪营地精确配置
        const campConfigs = {
            red_buff:    { hp: 3300, atk: 136, range: 150, speed: 0.83, gold: 58, xp: 68, def: 168, mdef: 120, atkType:'melee' },
            blue_buff:   { hp: 3300, atk: 136, range: 150, speed: 0.83, gold: 58, xp: 68, def: 168, mdef: 120, atkType:'melee' },
            chijia:      { hp: 3300, atk: 136, range: 150, speed: 0.83, gold: 58, xp: 68, def: 168, mdef: 120, atkType:'melee' },
            shanhao_big: { hp: 1584, atk: 85,  range: 400, speed: 0.67, gold: 24, xp: 34, def: 480, mdef: 48,  atkType:'ranged' },
            shanhao_sml: { hp: 792,  atk: 60,  range: 400, speed: 0.67, gold: 12, xp: 17, def: 480, mdef: 48,  atkType:'ranged' },
            liezhi:      { hp: 2805, atk: 115, range: 150, speed: 1.0,  gold: 51, xp: 68, def: 168, mdef: 120, atkType:'melee' },
            luxi:        { hp: 2046, atk: 128, range: 150, speed: 0.83, gold: 34, xp: 44, def: 168, mdef: 120, atkType:'melee' },
            yebao:       { hp: 1980, atk: 128, range: 150, speed: 1.0,  gold: 34, xp: 44, def: 168, mdef: 120, atkType:'melee' }
        };
        // 多体营地映射
        const campMap = {
            chijia: 'chijia',
            liezhi: 'liezhi',
            shanhao: unitIndex === 0 ? 'shanhao_big' : 'shanhao_sml',
            luxi_yebao: unitIndex === 0 ? 'luxi' : 'yebao',
            red_buff: 'red_buff',
            blue_buff: 'blue_buff'
        };
        const cfgKey = campMap[campType] || campType;
        const cc = campConfigs[cfgKey] || {};
        if (isCamp) {
            this.baseHp = cc.hp || 1500; this.maxHp = this.baseHp; this.hp = this.maxHp;
            this.baseAtk = cc.atk || 60; this.attackDamage = this.baseAtk;
            this.attackRange = cc.range || 150; this.attackSpeed = cc.speed || 0.7;
            this.goldValue = cc.gold || 30; this.xpValue = cc.xp || 35;
            this.defense = cc.def || 168; this.magicDef = cc.mdef || 120;
            this.atkType = cc.atkType || 'melee';
            this.radius = 25; this.refreshInterval = 70;
            this.respawnTimer = 40; // 70-30=40, 30秒后首次刷新
            this.dead = true;
            this.aggroRange = 500; this.chaseRange = 800;
            this.isCamp = true;
        } else {
            this.maxHp = isBaron ? 5000 : 3000; this.hp = this.maxHp;
            this.attackDamage = isBaron ? 120 : 85;
            this.attackRange = 200; this.attackSpeed = 0.7;
            this.goldValue = isBaron ? 30 : 105; this.xpValue = isBaron ? 50 : 0;
            this.refreshInterval = isBaron ? 270 : 180;
            this.respawnTimer = isBaron ? -210 : 60;  // 主宰8分钟 暴君2分钟
            this.dead = true;
        }
        this.spawnX = x; this.spawnY = y;
        this.threatMap = new Map();
        this.resetTimer = 0;
    }

    // 成长：按游戏时间缩放 HP 和 ATK
    applyGrowth(gameTime) {
        if (!this.isCamp) return;
        const minutes = gameTime / 60;
        let hpMul = 1;
        if (minutes <= 10) hpMul += minutes * 0.05;
        else if (minutes <= 15) hpMul += 10 * 0.05 + (minutes - 10) * 0.03;
        else hpMul += 10 * 0.05 + 5 * 0.03; // 15分钟封顶
        const atkMul = 1 + Math.min(minutes, 15) * 0.02;
        this.maxHp = Math.floor(this.baseHp * hpMul);
        if (this.hp > this.maxHp) this.hp = this.maxHp;
        this.attackDamage = Math.floor(this.baseAtk * atkMul);
    }

    evolve(gameTime) {
        if (!this.evolved && gameTime >= 600) { // 10分钟进化
            this.evolved = true;
            if (this.type === 'baron') {
                this.maxHp = 8000; this.hp = this.maxHp; this.attackDamage = 180;
            } else {
                this.maxHp = 5000; this.hp = this.maxHp; this.attackDamage = 130;
            }
            this.refreshInterval = this.type === 'baron' ? 300 : 240; // 进化后5分钟/4分钟
        }
    }

    onDeath(source, game) {
        const killerTeam = source ? source.team : (this.lastHitSource ? this.lastHitSource.team : -1);
        if (killerTeam === -1) return;
        // 击杀金币分配
        if (source instanceof Hero) source.gold += this.goldValue;
        for (const h of game.heroes) {
            if (h.team === killerTeam && !h.dead) {
                // 队友金币
                if (h !== source) h.gold += this.type === 'baron' ? 20 : 70;
                // 团队经验
                h.xp += this.type === 'baron' ? 50 : 300;
                if (this.type === 'dragon') {
                    // 龙魂层数（最多3层）
                    if (!h._dragonStacks) h._dragonStacks = 0;
                    h._dragonStacks = Math.min(3, h._dragonStacks + 1);
                    h.buffDragonTimer = 0; // 不再用计时，用层数
                } else if (this.type === 'baron') {
                    h.buffBaronTimer = 90;
                    // 主宰先锋：接下来3波兵替换
                    game._baronWavesLeft = 3;
                }
            }
        }
    }

    addThreat(hero, amount) {
        if (!hero || hero.dead) return;
        const current = this.threatMap.get(hero.id) || 0;
        this.threatMap.set(hero.id, current + amount);
    }

    getTopThreatTarget(game) {
        let best = null, bestThreat = 0;
        for (const [heroId, threat] of this.threatMap) {
            if (threat <= 0) continue;
            const hero = game.heroes.find(h => h.id === heroId);
            if (!hero || hero.dead) { this.threatMap.delete(heroId); continue; }
            const d = dist(this, hero);
            if (d > 1200) continue;
            if (threat > bestThreat) { bestThreat = threat; best = hero; }
        }
        return best;
    }

    findClosestHero(game, range = 900) {
        let closest = null, minD = Infinity;
        for (const h of game.heroes) {
            const d = dist(this, h);
            if (!h.dead && d < minD && d < range) { minD = d; closest = h; }
        }
        return closest;
    }

    update(dt, game) {
        if (this.dead) {
            this.respawnTimer += dt;
            if (this.respawnTimer >= this.refreshInterval) {
                this.dead = false; this.hp = this.maxHp; this.respawnTimer = 0;
                this.aggroTarget = null; this.threatMap.clear(); this.resetTimer = 0;
                this.x = this.spawnX; this.y = this.spawnY;
                this.applyGrowth(game.time);
                this.evolve(game.time);
            }
            return;
        }

        // 营地持续成长
        this.applyGrowth(game.time);

        // 威胁值衰减
        for (const [heroId, threat] of this.threatMap) {
            this.threatMap.set(heroId, threat * (1 - 0.05 * dt));
        }

        let target = this.getTopThreatTarget(game);
        if (!target) {
            target = this.findClosestHero(game, this.aggroRange || 900);
            if (target) this.addThreat(target, 1);
        }
        this.aggroTarget = target;

        if (!this.aggroTarget || dist(this, this.aggroTarget) > (this.chaseRange || 1200)) {
            this.aggroTarget = null;
            this.resetTimer += dt;
            const dHome = dist(this, { x: this.spawnX, y: this.spawnY });
            if (dHome > 20) {
                const retSpeed = this.isCamp ? 350 : 500;
                const angle = angleTo(this, { x: this.spawnX, y: this.spawnY });
                this.x += Math.cos(angle) * retSpeed * dt;
                this.y += Math.sin(angle) * retSpeed * dt;
                if (this.resetTimer > 3) {
                    this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.15 * dt);
                }
            } else {
                // 营地小范围巡逻
                if (this.isCamp) {
                    if (!this._patrolAngle) this._patrolAngle = Math.random() * Math.PI * 2;
                    if (!this._patrolTimer) this._patrolTimer = 0;
                    this._patrolTimer += dt;
                    if (this._patrolTimer > 3) { this._patrolTimer = 0; this._patrolAngle = Math.random() * Math.PI * 2; }
                    const offset = 40 * Math.sin(this._patrolTimer * 2);
                    this.x = this.spawnX + Math.cos(this._patrolAngle) * offset;
                    this.y = this.spawnY + Math.sin(this._patrolAngle) * offset;
                }
                this.hp = Math.min(this.maxHp, this.hp + this.maxHp * 0.2 * dt);
                this.resetTimer = 0;
                this.threatMap.clear();
            }
        } else {
            this.resetTimer = 0;
            const d = dist(this, this.aggroTarget);
            if (d <= this.attackRange) {
                if (this.attackCd <= 0) {
                    if (this.atkType === 'ranged') {
                        game.projectiles.push(new Projectile(game.nextId++, this.x, this.y, this.aggroTarget, -1, 'monster_arrow', this.attackDamage, 0, 0, 99, 10, this));
                    } else {
                        this.aggroTarget.takeDamage(this.attackDamage, this, game);
                    }
                    this.attackCd = 1 / this.attackSpeed;
                }
            } else {
                const angle = angleTo(this, this.aggroTarget);
                this.x += Math.cos(angle) * 150 * dt;
                this.y += Math.sin(angle) * 150 * dt;
            }
        }
        if (this.attackCd > 0) this.attackCd -= dt;
    }
}

class Projectile {
    constructor(id, x, y, target, team, type, damage, vx, vy, life, radius, source = null) {
        this.id = id; this.x = x; this.y = y; this.target = target; this.team = team;
        this.type = type; this.damage = damage; this.vx = vx || 0; this.vy = vy || 0;
        this.life = life || 99; this.radius = radius || 18;
        this.speed = type === 'q' ? 650 : (type === 'auto' ? 800 : 700);
        this.dead = false;
        this.source = source; // 用于命中音效归属
        this.penetrating = (type === 'q_penetrate'); // 穿透弹道（神射手 Q）
        this.hitTargets = new Set(); // 已命中目标 ID 集合
        this.penetrationCount = 0;    // 穿透计数（伤害衰减用）
        this.baseDamage = damage;     // 基础伤害（衰减计算参照）
    }
    update(dt, game) {
        if (this.dead) return;
        this.life -= dt;
        if (this.life <= 0) { this.dead = true; return; }

        if (this.target && !this.target.dead) {
            const angle = angleTo(this, this.target);
            this.x += Math.cos(angle) * this.speed * dt;
            this.y += Math.sin(angle) * this.speed * dt;
            if (dist(this, this.target) < this.target.radius + this.radius) {
                if (this.source instanceof Hero && (this.type === 'auto' || this.type === 'q' || this.type === 'q_penetrate')) {
                    game.broadcastSound('hit', this.target.x, this.target.y, { sourceRole: this.source.role });
                }
                if (!this.penetrating || !this.hitTargets.has(this.target.id)) {
                    let dmg = this.damage;
                    if (this.penetrating && this.penetrationCount > 0) {
                        dmg = Math.floor(this.baseDamage * Math.pow(0.8, this.penetrationCount));
                    }
                    this.target.takeDamage(dmg, this.source, game);
                    // 奥术师 Q 击杀刷新
                    if (this.target.dead && this.skillSlot === 'q' && this.source.role === 'mage') {
                        this.source.mp = Math.min(this.source.maxMp, this.source.mp + this.source.skillQ.mpCost * 0.5);
                        this.source.skillQ.cd = 0;
                    }
                }
                if (this.penetrating) {
                    this.hitTargets.add(this.target.id);
                    this.penetrationCount++;
                } else {
                    this.dead = true;
                }
            }
        } else if (this.vx !== 0 || this.vy !== 0) {
            this.x += this.vx * dt; this.y += this.vy * dt;
            for (const e of [...game.heroes, ...game.minions, ...game.towers, ...game.monsters]) {
                if (e.team !== this.team && !e.dead && dist(this, e) < e.radius + this.radius) {
                    if (this.source instanceof Hero) {
                        game.broadcastSound('hit', e.x, e.y, { sourceRole: this.source.role });
                    }
                    if (!this.penetrating || !this.hitTargets.has(e.id)) {
                        let dmg = this.damage;
                        if (this.penetrating && this.penetrationCount > 0) {
                            dmg = Math.floor(this.baseDamage * Math.pow(0.8, this.penetrationCount));
                        }
                        e.takeDamage(dmg, this.source, game);
                        // 奥术师 Q 击杀刷新
                        if (e.dead && this.skillSlot === 'q' && this.source.role === 'mage') {
                            this.source.mp = Math.min(this.source.maxMp, this.source.mp + this.source.skillQ.mpCost * 0.5);
                            this.source.skillQ.cd = 0;
                        }
                    }
                    if (this.penetrating) {
                        this.hitTargets.add(e.id);
                        this.penetrationCount++;
                    } else {
                        this.dead = true; break;
                    }
                }
            }
        } else {
            this.dead = true;
        }
        if (this.x < 0 || this.x > MAP_WIDTH || this.y < 0 || this.y > MAP_HEIGHT) this.dead = true;
    }
}

class Effect {
    constructor(id, type, x, y, radius, life) {
        this.id = id; this.type = type; this.x = x; this.y = y;
        this.radius = radius; this.life = life; this.maxLife = life;
    }
    update(dt) { this.life -= dt; }
}

class DelayedEffect {
    // 延迟 AOE 效果（奥术师 W 缚灵法阵）
    constructor(id, x, y, radius, delay, damage, source, game) {
        this.id = id; this.x = x; this.y = y; this.radius = radius;
        this.delay = delay; this.damage = damage; this.source = source;
        this.timer = 0; this.triggered = false; this.dead = false;
        this.rootTargets = false; // 是否定身目标
        // 广播警告圈
        if (game && game.addEffect) {
            game.addEffect('warn_circle', x, y, radius, delay);
        }
    }
    update(dt, game) {
        if (this.dead || this.triggered) return;
        this.timer += dt;
        if (this.timer >= this.delay) {
            this.triggered = true;
            // 对范围内敌人造成伤害
            const enemies = [...game.heroes, ...game.minions, ...game.towers, ...game.monsters]
                .filter(e => e.team !== this.source.team && !e.dead);
            for (const e of enemies) {
                if (dist(this, e) < this.radius + e.radius) {
                    e.takeDamage(this.damage, this.source, game);
                    if (this.rootTargets && e instanceof Hero) {
                        e.rooted = true;
                        e.rootTimer = 1;
                    }
                }
            }
            game.addEffect('burst', this.x, this.y, this.radius, 0.3);
            game.broadcastSound('skill', this.x, this.y, { slot: 'w', role: this.source.role });
            this.dead = true;
        }
    }
}

class VortexEffect {
    // 万象天引：持续牵引敌人向中心
    constructor(id, x, y, radius, life, source) {
        this.id = id; this.x = x; this.y = y; this.radius = radius;
        this.life = life; this.maxLife = life;
        this.source = source; this.speed = 400; // 每秒牵引速度
    }
    update(dt, game) {
        this.life -= dt;
        // 每 tick 拉扯范围内敌人
        const pullForce = this.speed * dt;
        for (const e of [...game.heroes, ...game.minions]) {
            if (e === this.source || e.dead || e.team === this.source.team) continue;
            const d = dist(this, e);
            if (d < this.radius && d > 10) {
                const angle = angleTo(e, this);
                e.x += Math.cos(angle) * pullForce;
                e.y += Math.sin(angle) * pullForce;
                e.x = clamp(e.x, e.radius || 20, MAP_WIDTH - (e.radius || 20));
                e.y = clamp(e.y, e.radius || 20, MAP_HEIGHT - (e.radius || 20));
            }
        }
    }
}

// ==================== 游戏管理 ====================
class Game {
    constructor() {
        this.state = 'waiting';
        this.time = 0; this.winner = null; this.nextId = 1;
        this.heroes = []; this.minions = []; this.towers = []; this.monsters = [];
        this.projectiles = []; this.effects = [];
        this.delayedEffects = []; this.vortexEffects = [];
        this.lastSpawn = -20; this.players = new Map();  // 首波10秒刷新
        this.resetTimer = null;
        this.goldHistory = []; // 经济曲线 [{t, blueGold, redGold}]
        this.lastGoldHistory = 0;
        this._frenzyWavesLeft = 0; // 击杀狂怒剩余波数
        this._baronWavesLeft = 0;  // 主宰先锋剩余波数
        this.bushes = mapData.bushes;
    }

    isInBush(x, y) {
        for (const b of this.bushes) {
            if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) return true;
        }
        return false;
    }

    isWall(x, y, radius = 0) {
        for (const w of mapData.walls) {
            if (x + radius > w.x && x - radius < w.x + w.w && y + radius > w.y && y - radius < w.y + w.h) return true;
        }
        return false;
    }

    getFountain(team) {
        const f = mapData.fountains.find(f => f.team === team);
        return f ? { x: f.x, y: f.y } : { x: MAP_WIDTH / 2, y: MAP_HEIGHT / 2 };
    }

    canSee(viewer, target) {
        if (!(target instanceof Hero)) return true;
        const targetInBush = this.isInBush(target.x, target.y);
        if (!targetInBush) return true;
        // 草丛内移动：300 码可见（草丛晃动效果）
        if (target.moveTarget && target.stillTimer < 1) {
            const viewerInBush = this.isInBush(viewer.x, viewer.y);
            if (viewerInBush && dist(viewer, target) < 350) return true;
            if (dist(viewer, target) < 300) return true;
            return false;
        }
        // 静止 1 秒+：完全隐身，180 码才可见
        const viewerInBush = this.isInBush(viewer.x, viewer.y);
        if (viewerInBush && dist(viewer, target) < 250) return true;
        if (dist(viewer, target) < 180) return true;
        return false;
    }

    reset() {
        this.state = 'waiting';
        this.time = 0; this.winner = null; this.nextId = 1;
        this.heroes = []; this.minions = []; this.towers = []; this.monsters = [];
        this.projectiles = []; this.effects = [];
        this.delayedEffects = []; this.vortexEffects = [];
        this.lastSpawn = -20; this.players = new Map();  // 首波10秒刷新
        this.resetTimer = null;
        this.goldHistory = [];
        this.lastGoldHistory = 0;
        this._frenzyWavesLeft = 0;
        this._baronWavesLeft = 0;
        this.broadcast({ type: 'reset', message: '房间已重置，可重新加入' });
    }

    addPlayer(ws, role) {
        const blueCount = this.heroes.filter(h => h.team === TEAM_BLUE && !h.dead).length;
        const redCount = this.heroes.filter(h => h.team === TEAM_RED && !h.dead).length;
        var team;
        if (blueCount < redCount) team = TEAM_BLUE;
        else if (redCount < blueCount) team = TEAM_RED;
        else team = Math.random() < 0.5 ? TEAM_BLUE : TEAM_RED;
        const x = team === TEAM_BLUE ? 300 : MAP_WIDTH - 300;
        const y = MAP_HEIGHT / 2 + (this.heroes.length - (team === TEAM_BLUE ? 0 : PLAYERS_PER_TEAM)) * 120;
        const hero = new Hero(this.nextId++, x, y, team, role);
        this.heroes.push(hero);
        this.players.set(ws, hero);
        ws.hero = hero;

        if (this.heroes.length >= PLAYERS_PER_TEAM * 2) {
            this.start();
        }
    }

    removePlayer(ws) {
        const hero = this.players.get(ws);
        if (hero) { hero.dead = true; this.players.delete(ws); this.heroes = this.heroes.filter(h => h !== hero); }
        if (this.players.size === 0) {
            if (this.resetTimer) { clearTimeout(this.resetTimer); this.resetTimer = null; }
            this.reset();
        }
    }

    start() {
        this.state = 'playing';
        for (const t of mapData.towers) {
            this.towers.push(new Tower(this.nextId++, t.x, t.y, t.team, t.tier || 'outer'));
        }
        for (const m of mapData.monsters) {
            this.monsters.push(new Monster(this.nextId++, m.x, m.y, m.type));
        }
        for (const c of (mapData.camps || [])) {
            const count = c.count || 1;
            for (let i = 0; i < count; i++) {
                const ox = i > 0 ? (Math.random() - 0.5) * 80 : 0;
                const oy = i > 0 ? (Math.random() - 0.5) * 80 : 0;
                this.monsters.push(new Monster(this.nextId++, c.x + ox, c.y + oy, 'camp', c.type, i));
            }
        }

        this.broadcast({ type: 'start', message: '对局开始！3v3 双路推塔' });
    }

    handleInput(ws, action) {
        const hero = this.players.get(ws);
        if (!hero) return;

        // 调试命令：任何状态都可执行
        if (action.type === 'upgrade_skill' && hero) {
            hero.upgradeSkill(action.slot);
            return;
        }
        if (action.type === 'dev_levelup' && hero) {
            hero.xp = hero.xpToLevel; hero.levelUp(this); return;
        }
        if (action.type === 'dev_gold' && hero) {
            hero.gold += 1000; return;
        }
        if (action.type === 'dev_respawn' && hero) {
            hero.dead = false; hero.hp = hero.maxHp; hero.mp = hero.maxMp;
            const f = this.getFountain(hero.team); hero.x = f.x; hero.y = f.y; return;
        }
        if (action.type === 'dev_end_game' && hero) {
            // 立即结束游戏，当前玩家所在队伍获胜
            this.state = 'ended'; this.winner = hero.team;
            const stats = this.generateEndStats();
            this.broadcast({ type: 'end', winner: hero.team === TEAM_BLUE ? '蓝方' : '红方', stats });
            if (!this.resetTimer) this.resetTimer = setTimeout(() => this.reset(), 15000);
            return;
        }
        if (action.type === 'dev_refresh_monsters') {
            for (const m of this.monsters) {
                m.dead = false; m.hp = m.maxHp; m.respawnTimer = 0;
            }
            return;
        }
        if (action.type === 'dev_spawn_bot') {
            // 在鼠标位置生成一个敌方 AI 英雄（仅调试用）
            const team = hero.team === TEAM_BLUE ? TEAM_RED : TEAM_BLUE;
            const bot = new Hero(this.nextId++, clamp(action.x, 100, MAP_WIDTH - 100), clamp(action.y, 100, MAP_HEIGHT - 100), team, action.role || 'warrior');
            bot.isBot = true;
            this.heroes.push(bot);
            // 自动开局
            if (this.state === 'waiting' && this.heroes.filter(h => !h.dead).length >= 2) {
                this.start();
            }
            return;
        }

        if (this.state !== 'playing') return;
        if (action.type === 'move') {
            hero.moveTarget = { x: clamp(action.x, 0, MAP_WIDTH), y: clamp(action.y, 0, MAP_HEIGHT) };
        } else if (action.type === 'attack') {
            const target = this.findEntityById(action.targetId);
            if (target) hero.basicAttack(target, this);
        } else if (action.type === 'skill') {
            const target = action.targetId ? this.findEntityById(action.targetId) : { x: action.x, y: action.y };
            hero.castSkill(action.slot, target, this);
        } else if (action.type === 'recall') {
            hero.startRecall();
        } else if (action.type === 'cancel_channel') {
            if (hero.channeling) {
                hero.channeling = false;
                hero._channelTickAcc = 0;
            }
        } else if (action.type === 'global_tp') {
            if (hero.level >= 3 && hero.globalTpCd <= 0 && !hero.isGlobalTping) {
                const tpTarget = this.findEntityById(action.targetId);
                if (tpTarget && !tpTarget.dead && tpTarget.team === hero.team) {
                    hero.isGlobalTping = true;
                    hero.globalTpTimer = 0;
                    hero.globalTpTarget = tpTarget;
                }
            }
        }
    }

    findEntityById(id) {
        for (const e of [...this.heroes, ...this.minions, ...this.towers, ...this.monsters]) {
            if (e.id === id && !e.dead) return e;
        }
        return null;
    }

    addEffect(type, x, y, radius, life) { this.effects.push(new Effect(this.nextId++, type, x, y, radius, life)); }

    updateBotAI(bot, dt) {
        bot.attackCd -= dt;
        if (bot.attackCd < 0) bot.attackCd = 0;
        ['Q', 'W', 'E', 'R'].forEach(s => { const sk = bot['skill' + s]; if (sk.cd > 0) sk.cd -= dt; });

        // 血量低回城
        if (bot.hp < bot.maxHp * 0.25 && !bot.isRecalling) {
            bot.startRecall();
            return;
        }

        // 找最近敌人
        let target = null, minD = Infinity;
        for (const e of [...this.heroes, ...this.minions, ...this.towers, ...this.monsters]) {
            if (e.team !== bot.team && !e.dead) {
                const d = dist(bot, e);
                if (d < minD) { minD = d; target = e; }
            }
        }

        if (target) {
            bot.faceAngle = angleTo(bot, target);
            if (minD > bot.attackRange * 0.8) {
                const angle = angleTo(bot, target);
                const newX = clamp(bot.x + Math.cos(angle) * bot.moveSpeed * dt, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
                const newY = clamp(bot.y + Math.sin(angle) * bot.moveSpeed * dt, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
                const resolved = resolveMovement(bot, newX, newY, this);
                bot.x = resolved.x;
                bot.y = resolved.y;
                bot.cancelRecall();
            }
            if (minD <= bot.attackRange + 30 && bot.attackCd <= 0) {
                if (bot.role === 'mage' || bot.role === 'archer') {
                    this.projectiles.push(new Projectile(this.nextId++, bot.x, bot.y, target, bot.team, 'auto', bot.attackDamage, 0, 0, 99, 18, bot));
                } else {
                    this.broadcastSound('hit', target.x, target.y, { sourceRole: bot.role });
                    target.takeDamage(bot.attackDamage, bot, this);
                }
                bot.attackCd = 1 / bot.attackSpeed;
            }
            // 随机放技能
            for (const slot of ['q', 'w', 'e', 'r']) {
                const skill = bot['skill' + slot.toUpperCase()];
                if (skill.cd <= 0 && bot.mp >= skill.mpCost && !(slot === 'r' && !bot.skillR.unlocked) && minD < skill.range + 50 && Math.random() < 0.02) {
                    bot.castSkill(slot, target, this);
                    break;
                }
            }
        } else {
            // 没目标往敌方主堡推
            const goalX = bot.team === TEAM_BLUE ? MAP_WIDTH - 200 : 200;
            const angle = angleTo(bot, { x: goalX, y: MAP_HEIGHT / 2 });
            const newX = clamp(bot.x + Math.cos(angle) * bot.moveSpeed * 0.6 * dt, HERO_RADIUS, MAP_WIDTH - HERO_RADIUS);
            const newY = clamp(bot.y + Math.sin(angle) * bot.moveSpeed * 0.6 * dt, HERO_RADIUS, MAP_HEIGHT - HERO_RADIUS);
            const resolved = resolveMovement(bot, newX, newY, this);
            bot.x = resolved.x;
            bot.y = resolved.y;
        }
    }

    spawnMinions() {
        if (this.time - this.lastSpawn >= 30) {
            this.lastSpawn = this.time;
            if (this._frenzyWavesLeft > 0) this._frenzyWavesLeft--;
            const isBaronWave = this._baronWavesLeft > 0;
            if (isBaronWave) this._baronWavesLeft--;
            // 每 5 分钟增援波 +1 近战兵
            const isReinforce = Math.floor(this.time / 300) > Math.floor((this.time - 30) / 300);
            for (const lane of ['top', 'bot']) {
                const y = lane === 'top' ? LANE_TOP_Y : LANE_BOT_Y;
                // 检查该路二塔是否被破 → 超级兵
                const innerTowerDead = this.towers.some(t => t.team === this.team && t.tier === 'inner' && t.dead);
                const superCannon = innerTowerDead;
                // 2~3 近战 + 1 炮车
                const meleeCount = isReinforce ? 3 : 2;
                for (let i = 0; i < meleeCount; i++) {
                    const offset = (i - (meleeCount - 1) / 2) * 80;
                    this.minions.push(new Minion(this.nextId++, 150, y + offset, TEAM_BLUE, lane, 'melee', this.time));
                    this.minions.push(new Minion(this.nextId++, MAP_WIDTH - 150, y + offset, TEAM_RED, lane, 'melee', this.time));
                }
                this.minions.push(new Minion(this.nextId++, 150, y, TEAM_BLUE, lane, 'cannon', this.time, superCannon));
                this.minions.push(new Minion(this.nextId++, MAP_WIDTH - 150, y, TEAM_RED, lane, 'cannon', this.time, superCannon));
                if (this._frenzyWavesLeft > 0) {
                    const newest = this.minions.slice(-(meleeCount + 1) * 2);
                    newest.forEach(m => { m.frenzyBuffed = true; });
                }
            }
        }
    }

    checkWin() {
        const blueMain = this.towers.find(t => t.team === TEAM_BLUE && t.isMain && !t.dead);
        const redMain = this.towers.find(t => t.team === TEAM_RED && t.isMain && !t.dead);
        if (!blueMain) return TEAM_RED;
        if (!redMain) return TEAM_BLUE;
        return null;
    }

    update(dt) {
        if (this.state !== 'playing') return;
        this.time += dt;

        // 每 5 秒记录一次双方总金币
        if (this.time - this.lastGoldHistory >= 5) {
            this.lastGoldHistory = this.time;
            const blueGold = this.heroes.filter(h => h.team === TEAM_BLUE).reduce((sum, h) => sum + h.gold, 0);
            const redGold = this.heroes.filter(h => h.team === TEAM_RED).reduce((sum, h) => sum + h.gold, 0);
            this.goldHistory.push({ t: Math.round(this.time), blueGold, redGold });
        }

        this.spawnMinions();
        for (const h of this.heroes) {
            h.update(dt, this);
            h.updateHitFlash(dt);
            if (h.isBot && !h.dead) this.updateBotAI(h, dt);
        }
        for (const m of this.minions) { m.update(dt, this); m.updateHitFlash(dt); }
        for (const t of this.towers) { t.update(dt, this); t.updateHitFlash(dt); }
        for (const m of this.monsters) { m.update(dt, this); m.updateHitFlash(dt); }
        for (const p of this.projectiles) p.update(dt, this);
        for (const e of this.effects) e.update(dt);
        for (const de of this.delayedEffects) de.update(dt, this);
        for (const ve of this.vortexEffects) ve.update(dt, this);

        this.minions = this.minions.filter(e => !e.dead);
        this.towers = this.towers.filter(e => !e.dead);
        this.projectiles = this.projectiles.filter(e => !e.dead);
        this.effects = this.effects.filter(e => e.life > 0);
        this.delayedEffects = this.delayedEffects.filter(e => !e.dead);
        this.vortexEffects = this.vortexEffects.filter(e => e.life > 0);

        const winner = this.checkWin();
        if (winner !== null) {
            this.state = 'ended'; this.winner = winner;
            const stats = this.generateEndStats();
            this.broadcast({ type: 'end', winner: winner === TEAM_BLUE ? '蓝方' : '红方', stats });
            if (!this.resetTimer) {
                this.resetTimer = setTimeout(() => this.reset(), 15000);
            }
        }
    }

    generateEndStats() {
        const heroes = this.heroes.map(h => ({
            id: h.id,
            team: h.team,
            role: h.role,
            level: h.level,
            gold: h.gold,
            kills: h.kills,
            deaths: h.deaths,
            assists: h.stats.assists || 0,
            damageDealt: Math.round(h.stats.damageDealt),
            damageTaken: Math.round(h.stats.damageTaken),
            healing: Math.round(h.stats.healing)
        }));
        const teamKills = {
            [TEAM_BLUE]: this.heroes.filter(h => h.team === TEAM_BLUE).reduce((s, h) => s + h.kills, 0),
            [TEAM_RED]: this.heroes.filter(h => h.team === TEAM_RED).reduce((s, h) => s + h.kills, 0)
        };
        return { heroes, teamKills, goldHistory: this.goldHistory };
    }

    broadcast(data) {
        const msg = typeof data === 'string' ? data : JSON.stringify(data);
        for (const ws of this.players.keys()) {
            if (ws.readyState === WebSocket.OPEN) ws.send(msg);
        }
    }

    broadcastDamageNumber(x, y, amount, isCrit) {
        const msg = JSON.stringify({ type: 'damage_number', x: Math.round(x), y: Math.round(y), amount, isCrit });
        for (const ws of this.players.keys()) {
            if (ws.readyState === WebSocket.OPEN) ws.send(msg);
        }
    }

    broadcastShake(intensity, duration) {
        const msg = JSON.stringify({ type: 'shake', intensity, duration });
        for (const ws of this.players.keys()) {
            if (ws.readyState === WebSocket.OPEN) ws.send(msg);
        }
    }

    broadcastSound(soundType, x, y, data = {}) {
        const msg = JSON.stringify({ type: 'sound', soundType, x: Math.round(x), y: Math.round(y), ...data });
        for (const ws of this.players.keys()) {
            if (ws.readyState === WebSocket.OPEN) ws.send(msg);
        }
    }

    broadcastState() {
        if (this.players.size === 0) return;
        const state = serializeState(this);
        for (const ws of this.players.keys()) {
            if (ws.readyState === WebSocket.OPEN) ws.send(state);
        }
    }
}

// ==================== HTTP + WebSocket 服务 ====================
const server = http.createServer((req, res) => {
    if (req.url === '/map.json') {
        fs.readFile(path.join(__dirname, 'map.json'), (err, data) => {
            if (err) { res.writeHead(404); res.end('Not found'); }
            else { res.writeHead(200, { 'Content-Type': 'application/json', 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' }); res.end(data); }
        });
        return;
    }

    let filePath = path.join(__dirname, '../client', req.url === '/' ? 'index.html' : req.url);
    const ext = path.extname(filePath);
    const contentType = {
        '.html': 'text/html',
        '.js': 'application/javascript',
        '.css': 'text/css',
        '.json': 'application/json'
    }[ext] || 'application/octet-stream';

    fs.readFile(filePath, (err, data) => {
        if (err) { res.writeHead(404); res.end('Not found'); }
        else { res.writeHead(200, { 'Content-Type': contentType, 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' }); res.end(data); }
    });
});

const wss = new WebSocket.Server({ server });
const game = new Game();

wss.on('connection', (ws) => {
    console.log('玩家连接');
    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            if (data.type === 'admin_reset') {
                if (game.resetTimer) { clearTimeout(game.resetTimer); game.resetTimer = null; }
                game.reset();
                return;
            }
            if (data.type === 'join') {
                if (game.state === 'ended') {
                    if (game.resetTimer) { clearTimeout(game.resetTimer); game.resetTimer = null; }
                    game.reset();
                }
                if (game.heroes.filter(h => !h.dead).length >= PLAYERS_PER_TEAM * 2) {
                    ws.send(JSON.stringify({ type: 'error', message: '房间已满，请等待本局结束或 15 秒后自动重置' }));
                    ws.close(); return;
                }
                const validRoles = ['warrior', 'mage', 'archer'];
                const role = validRoles.includes(data.role) ? data.role : 'warrior';
                game.addPlayer(ws, role);
                ws.send(JSON.stringify({ type: 'joined', team: ws.hero.team, role: ws.hero.role, id: ws.hero.id }));
                // 广播当前玩家数
                const count = game.heroes.filter(h => !h.dead).length;
                game.broadcast({ type: 'player_count', count, max: PLAYERS_PER_TEAM * 2 });
            } else {
                game.handleInput(ws, data);
            }
        } catch (e) { console.error('消息处理失败', e); }
    });

    ws.on('close', () => {
        console.log('玩家断开');
        game.removePlayer(ws);
    });
    ws.send(JSON.stringify({ type: 'hello', message: '等待加入对局，发送 {type:"join", role:"warrior"|"mage"|"archer"}。本局结束后房间会自动重置。' }));
});

setInterval(() => {
    game.update(DT);
    game.broadcastState();
}, 1000 / TICK_RATE);

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
    console.log(`MOBA 3v3 PC 端原型服务器已启动：http://localhost:${PORT}`);
});
