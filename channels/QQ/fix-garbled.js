const fs = require('fs');
const p = 'D:/agent_workspace/channel/QQ/qq-bridge.js';
let c = fs.readFileSync(p, 'utf8');
c = c.replace("|| '���')", "|| '你好')");
fs.writeFileSync(p, c, 'utf8');
