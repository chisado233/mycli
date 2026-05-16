const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = __dirname;
const PACKAGE_ROOT = path.resolve(ROOT, '..');
const MYCLI_ROOT = path.resolve(PACKAGE_ROOT, '..');
const PUBLIC_DIR = path.join(ROOT, 'public');
const PORT = Number(process.env.STARTUP_UI_PORT || process.argv[2] || 46020);

function mycliPath() { return path.join(MYCLI_ROOT, 'mycli.ps1'); }
function runMycli(args) { return new Promise(resolve => { const child = spawn('pwsh.exe', ['-NoProfile','-ExecutionPolicy','Bypass','-File',mycliPath(),...args], { cwd: MYCLI_ROOT, windowsHide: true }); let stdout='', stderr=''; child.stdout.on('data',d=>stdout+=d.toString('utf8')); child.stderr.on('data',d=>stderr+=d.toString('utf8')); child.on('error',e=>resolve({ok:false,code:-1,stdout,stderr:e.message||String(e)})); child.on('close',code=>resolve({ok:code===0,code,stdout,stderr})); }); }
function parseJson(text, fallback) { try { const t=String(text||'').trim(); return t?JSON.parse(t):fallback; } catch { return fallback; } }
function arrayify(v) { if (Array.isArray(v)) return v; if (v === null || typeof v === 'undefined' || v === '') return []; return [v]; }
async function snapshot() { const [list,status] = await Promise.all([runMycli(['startup','commands','--json']), runMycli(['startup','status','--json'])]); const commands = arrayify(parseJson(list.stdout, [])); const info = parseJson(status.stdout, {}); return { generatedAt:new Date().toISOString(), commands, status: info, counts:{ total:commands.length, enabled:commands.filter(c=>c.enabled).length, disabled:commands.filter(c=>!c.enabled).length }, raw: (!list.ok||!status.ok)?{list,status}:null }; }
function readBody(req){return new Promise((resolve,reject)=>{let body='';req.on('data',c=>{body+=c.toString('utf8');if(body.length>1024*1024)reject(new Error('request body too large'))});req.on('end',()=>{try{resolve(body.trim()?JSON.parse(body):{})}catch(e){reject(e)}});req.on('error',reject)})}
function sendJson(res,status,data){res.writeHead(status,{'content-type':'application/json; charset=utf-8','cache-control':'no-store'});res.end(JSON.stringify(data))}
function contentType(file){if(file.endsWith('.html'))return'text/html; charset=utf-8';if(file.endsWith('.css'))return'text/css; charset=utf-8';if(file.endsWith('.js'))return'application/javascript; charset=utf-8';return'application/octet-stream'}

const server = http.createServer(async (req,res)=>{ const url = new URL(req.url,`http://${req.headers.host}`); if(url.pathname==='/api/snapshot'){sendJson(res,200,await snapshot());return} const m=url.pathname.match(/^\/api\/commands\/([^/]+)\/(enable|disable|remove)$/); if(m){ if(req.method!=='POST'){sendJson(res,405,{ok:false,error:'method not allowed'});return} await readBody(req).catch(()=>({})); const id=decodeURIComponent(m[1]); const action=m[2]; const result=await runMycli(['startup',action,id]); sendJson(res,200,{ok:result.ok,action,result,snapshot:await snapshot()}); return } if(url.pathname==='/api/run'&&req.method==='POST'){ await readBody(req).catch(()=>({})); const result=await runMycli(['startup','run']); sendJson(res,200,{ok:result.ok,result,snapshot:await snapshot()}); return } if(url.pathname==='/api/install'&&req.method==='POST'){ await readBody(req).catch(()=>({})); const result=await runMycli(['startup','install']); sendJson(res,200,{ok:result.ok,result,snapshot:await snapshot()}); return } const pathname=url.pathname==='/'?'/index.html':url.pathname; const file=path.normalize(path.join(PUBLIC_DIR,pathname)); if(!file.startsWith(PUBLIC_DIR)){res.writeHead(403);res.end('forbidden');return} fs.readFile(file,(err,data)=>{if(err){res.writeHead(404);res.end('not found');return}res.writeHead(200,{'content-type':contentType(file)});res.end(data)}) });
server.listen(PORT,'127.0.0.1',()=>console.log(`Startup UI: http://127.0.0.1:${PORT}`));
