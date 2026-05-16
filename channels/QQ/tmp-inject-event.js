const WebSocket = require('D:/agent_workspace/channel/QQ/node_modules/ws');
const ws = new WebSocket('ws://127.0.0.1:3001?access_token=chisado');
const event = {
  time: Math.floor(Date.now()/1000),
  self_id: 3279329186,
  post_type: 'message',
  message_type: 'group',
  sub_type: 'normal',
  message_id: 999001,
  group_id: 895102465,
  user_id: 381889153,
  raw_message: '彩叶在吗',
  message: [{ type: 'text', data: { text: '彩叶在吗' } }]
};
ws.on('open', () => { ws.send(JSON.stringify(event)); setTimeout(() => ws.close(), 2000); });
ws.on('error', e => { console.error(e); process.exit(1); });
