const WebSocket = require('ws');

const roles = ['warrior', 'mage', 'archer', 'warrior', 'mage', 'archer'];
const clients = [];
let stateCount = 0;
let started = false;

function log(idx, msg) {
    console.log(`P${idx + 1}: ${msg}`);
}

for (let i = 0; i < 6; i++) {
    const ws = new WebSocket('ws://localhost:8080');
    clients.push(ws);
    ws.idx = i;

    ws.on('open', () => {
        setTimeout(() => {
            ws.send(JSON.stringify({ type: 'join', role: roles[i] }));
        }, i * 200);
    });

    ws.on('message', (msg) => {
        const data = JSON.parse(msg);
        if (data.type === 'joined') {
            log(i, `joined team=${data.team} role=${data.role}`);
        } else if (data.type === 'start') {
            if (!started) {
                started = true;
                log(i, data.message);
            }
            // 随机移动和放技能
            setInterval(() => {
                if (ws.readyState === WebSocket.OPEN) {
                    const x = 1000 + Math.random() * 4000;
                    const y = 500 + Math.random() * 3000;
                    ws.send(JSON.stringify({ type: 'move', x, y }));
                }
            }, 800);
            setInterval(() => {
                if (ws.readyState === WebSocket.OPEN) {
                    const slot = ['q', 'w', 'e', 'r'][Math.floor(Math.random() * 4)];
                    ws.send(JSON.stringify({ type: 'skill', slot, x: 3000, y: 2000, targetId: null }));
                }
            }, 2500);
        } else if (data.type === 'end') {
            log(i, `END winner=${data.winner}`);
        } else if (data.state !== undefined) {
            stateCount++;
            if (stateCount % 200 === 0) {
                const aliveHeroes = data.heroes.filter(h => !h.dead).length;
                const aliveTowers = data.towers.filter(t => !t.dead).length;
                log(i, `tick=${data.t.toFixed(1)} heroes=${aliveHeroes}/6 towers=${aliveTowers} minions=${data.minions.length} monsters=${data.monsters.length}`);
            }
        }
    });

    ws.on('error', (e) => console.error(`P${i + 1} error`, e.message));
}

setTimeout(() => {
    console.log(`\nReceived ${stateCount} state updates`);
    clients.forEach(c => c.close());
    process.exit(0);
}, 20000);
