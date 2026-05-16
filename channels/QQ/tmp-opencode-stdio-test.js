const { spawn } = require('child_process');
const prompt = '在吗';
const p = spawn('cmd.exe', ['/c','opencode','run','--session','ses_22c37f348ffeV2JDLCJrT2UzqT', prompt, '--agent','jiuji-caiye','--model','MoreCode/gpt-5.4-nano','--dir','D:/agent_workspace','--format','json'], { cwd:'D:/agent_workspace', windowsHide:true, stdio:['ignore','pipe','pipe'], env:{...process.env, CI:'true'} });
let out='', err='';
const timer=setTimeout(()=>{console.log('TIMEOUT'); try{p.kill('SIGKILL')}catch{}}, 120000);
p.stdout.on('data', d=> out+=d.toString('utf8'));
p.stderr.on('data', d=> err+=d.toString('utf8'));
p.on('error', e=> console.error('error', e));
p.on('close', code=>{clearTimeout(timer); console.log('code',code); console.log('out',out.slice(-4000)); console.log('err',err.slice(-4000));});
