const fs = require('fs');
const p = 'D:/agent_workspace/channel/QQ/qq-bridge.js';
let c = fs.readFileSync(p, 'utf8');
const oldLine = '      `& ${JSON.stringify(config.mycli)} agent-cli run --agent ${JSON.stringify(config.agent)} --model ${JSON.stringify(config.model)} --cwd ${JSON.stringify(config.cwd)} --return_mode ${JSON.stringify(config.returnMode)} ${sessionId ? `--session ${JSON.stringify(sessionId)}` : `--session_name ${JSON.stringify(config.sessionName)}`} --prompt $promptText`';
const newLine = '      `$env:QQ_BRIDGE_PROMPT = $promptText`,\n      `& ${JSON.stringify(config.mycli)} agent-cli run --agent ${JSON.stringify(config.agent)} --model ${JSON.stringify(config.model)} --cwd ${JSON.stringify(config.cwd)} --return_mode ${JSON.stringify(config.returnMode)} ${sessionId ? `--session ${JSON.stringify(sessionId)}` : `--session_name ${JSON.stringify(config.sessionName)}`} --prompt $env:QQ_BRIDGE_PROMPT`';
if (!c.includes(oldLine)) throw new Error('old line not found');
c = c.replace(oldLine, newLine);
fs.writeFileSync(p, c, 'utf8');
