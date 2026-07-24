// 快速验证 end 消息中 stats 字段
const WebSocket = require('ws');

const ws = new WebSocket('ws://localhost:8080');

ws.on('open', () => {
    ws.send(JSON.stringify({ type: 'join', role: 'warrior' }));
});

ws.on('message', (msg) => {
    const data = JSON.parse(msg);
    if (data.type === 'joined') {
        console.log('已加入，1 秒后结束游戏');
        setTimeout(() => ws.send(JSON.stringify({ type: 'dev_end_game' })), 1000);
    } else if (data.type === 'end') {
        console.log('\n==== 收到 end 消息 ====');
        console.log('胜者:', data.winner);
        console.log('stats 字段存在:', !!data.stats);
        if (data.stats) {
            console.log('英雄数量:', data.stats.heroes.length);
            console.log('teamKills:', data.stats.teamKills);
            console.log('goldHistory 长度:', data.stats.goldHistory.length);
            console.log('英雄数据示例:', JSON.stringify(data.stats.heroes[0], null, 2));
        }
        ws.close();
        process.exit(0);
    } else if (data.type === 'error') {
        console.log('错误:', data.message);
    }
});

setTimeout(() => {
    console.log('超时');
    process.exit(1);
}, 10000);
