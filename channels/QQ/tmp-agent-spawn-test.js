const { spawn } = require('child_process');
const fs = require('fs');
const prompt = 'QQ message metadata: message_type=group; user_id=381889153; group_id=895102465; message_id=test.\nUser message:\n在吗';
function run(cmd, args, label) {
  return new Promise((resolve) => {
    console.log('---', label, '---');
    const p = spawn(cmd, args, { cwd: 'D:/agent_workspace', windowsHide: true, env: {...process.env, CI:'true', GIT_TERMINAL_PROMPT:'0', GCM_INTERACTIVE:'never', PIP_NO_INPUT:'1', PYTHONIOENCODING:'utf-8'} });
    let out='', err='';
    const timer=setTimeout(()=>{ console.log('TIMEOUT'); try{p.kill('SIGKILL')}catch{}; resolve();}, 120000);
    p.stdout.on('data', d => out += d.toString('utf8'));
    p.stderr.on('data', d => err += d.toString('utf8'));
    p.on('close', code => { clearTimeout(timer); console.log('code', code); console.log('out', out.slice(-2000)); console.log('err', err.slice(-2000)); resolve(); });
  });
}
(async()=>{
 await run('powershell.exe', ['-NoProfile','-ExecutionPolicy','Bypass','-File','D:/agent_workspace/capability-library/mycli/mycli.ps1','agent-cli','run','--agent','opencode/jiuji-caiye','--model','MoreCode/gpt-5.4-nano','--cwd','D:/agent_workspace','--return_mode','silent','--session','ses_22c37f348ffeV2JDLCJrT2UzqT','--prompt',prompt], 'powershell direct args');
 await run('pwsh.exe', ['-NoProfile','-ExecutionPolicy','Bypass','-File','D:/agent_workspace/capability-library/mycli/mycli.ps1','agent-cli','run','--agent','opencode/jiuji-caiye','--model','MoreCode/gpt-5.4-nano','--cwd','D:/agent_workspace','--return_mode','silent','--session','ses_22c37f348ffeV2JDLCJrT2UzqT','--prompt',prompt], 'pwsh direct args');
})();
