import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
const [entry, profile, op, ...args] = process.argv.slice(2);
const req=createRequire(entry);
const yaml=req('js-yaml');
const semver=req('semver');
const expr=new yaml.Type('tag:yaml.org,2002:js',{kind:'scalar',construct:s=>({__jsExpr:s}),predicate:x=>x&&typeof x==='object'&&Object.keys(x).length===1&&typeof x.__jsExpr==='string',represent:x=>x.__jsExpr});
const schema=yaml.DEFAULT_SCHEMA.extend([expr]);
const read=p=>yaml.load(fs.readFileSync(p,'utf8'),{schema});
const out=x=>console.log(JSON.stringify(x));
const sensitive=k=>/^(apiKey|password|secret|token|accessToken|refreshToken|authorization|x-api-key|x-dsh-auth-token)$/i.test(k);
function assertSafe(x){if(!x||typeof x!=='object')return;for(const [k,v] of Object.entries(x)){if(sensitive(k)&&typeof v==='string'&&v.length)throw Error('配置含内联凭据，拒绝将其复制到历史；请先通过官方凭据引用迁移：'+k);assertSafe(v)}}
function rows(x){if(!Array.isArray(x))return [];return x.flatMap(r=>[r,...rows(r.insert),...rows(Array.isArray(r.config)?r.config:[])])}
try {
 if(op==='validate'){const p=JSON.parse(fs.readFileSync(path.join(profile,'package.json'),'utf8'));for(const f of ['cordis.yml','cordis.patch.yml','pnpm-lock.yaml'])read(path.join(profile,f));out({valid:true,bundles:p.dsh.profile.bundles.length});}
 else if(op==='safe-copy'){const [src,dest]=args;const text=fs.readFileSync(src,'utf8');assertSafe(src.endsWith('.json')?JSON.parse(text):read(src));if(/\bsk-[A-Za-z0-9_-]{12,}/.test(text)||/[?&](token|key)=[^\s&]+/i.test(text))throw Error('拒绝备份包含凭据的文件');fs.copyFileSync(src,dest);out({copied:true});}
 else if(op==='plugins'){
  const p=JSON.parse(fs.readFileSync(path.join(profile,'package.json'),'utf8'));const patches=rows(read(path.join(profile,'cordis.patch.yml')));
  const items=Object.entries(p.dependencies??{}).map(([name,spec])=>{const file=path.join(profile,'node_modules',...name.split('/'),'package.json');let m={};if(fs.existsSync(file))m=JSON.parse(fs.readFileSync(file,'utf8'));let declared=[];const bp=m.dsh?.bundle?.patch;if(bp){for(const f of Array.isArray(bp)?bp:[bp]){const pp=path.resolve(path.dirname(file),f);if(fs.existsSync(pp))declared.push(...rows(read(pp)).map(r=>({id:r.id,name:r.name,disabled:r.disabled===true})).filter(r=>r.id))}}const warnings=[];for(const [peer,range] of Object.entries(m.peerDependencies??{})){if(!peer.startsWith('@deepseek-ai/'))continue;try{const installed=JSON.parse(fs.readFileSync(req.resolve(peer+'/package.json'),'utf8'));if(!semver.satisfies(installed.version,range,{includePrerelease:true}))warnings.push(peer+' installed='+installed.version+' requires='+range)}catch{warnings.push(peer+' 未提供')}}return {name,version:m.version??'missing',spec,source:/^(github:|git|https?:.*\.git)/.test(spec)?'GitHub/git':/^(file:|link:|\.?\.?[\\/])/.test(spec)?'local':'npm',bundle:!!bp,enabled:p.dsh.profile.bundles.includes(name),rows:declared.map(r=>{const over=patches.filter(p=>p.id===r.id).at(-1);return {...r,disabled:over&&'disabled'in over?over.disabled===true:r.disabled}}),peers:m.peerDependencies??{},compatibilityWarnings:warnings};});out(items);
 }
 else if(op==='peer-check'){
  const [metaFile,runtime]=args;const m=JSON.parse(fs.readFileSync(metaFile,'utf8'));const refused=[];for(const [name,range] of Object.entries(m.peerDependencies??{})){if(name.startsWith('@deepseek-ai/dsh')){let available=true;try{req.resolve(name+'/package.json')}catch{available=false}if(!available||!semver.satisfies(runtime,range,{includePrerelease:true}))refused.push({name,range,runtime,available});}}out({compatible:refused.length===0,refused});
 }
 else if(op==='runtime-check'){
  const [metaFile,node,pnpm,target]=args;const m=JSON.parse(fs.readFileSync(metaFile,'utf8'));const issues=[];
  if(!m.engines?.node)issues.push('官方目标版本没有可查证的 Node 要求');else if(!semver.satisfies(node.replace(/^v/,''),m.engines.node))issues.push('Node '+node+' 不符合 '+m.engines.node);
  const wanted=m.packageManager?.match(/^pnpm@([\d.]+)/)?.[1];if(!wanted)issues.push('官方目标版本没有可查证的 pnpm pin');else if(semver.major(pnpm)!==semver.major(wanted)||semver.lt(pnpm,wanted))issues.push('pnpm '+pnpm+' 与目标仓库 pin '+wanted+' 不匹配；先单独审阅并升级包管理器');
  const manifest=JSON.parse(fs.readFileSync(path.join(profile,'package.json'),'utf8'));
  for(const name of Object.keys(manifest.dependencies??{})){const file=path.join(profile,'node_modules',...name.split('/'),'package.json');if(!fs.existsSync(file))continue;const p=JSON.parse(fs.readFileSync(file,'utf8'));for(const [peer,range] of Object.entries(p.peerDependencies??{})){if(peer.startsWith('@deepseek-ai/dsh')&&!semver.satisfies(target,range,{includePrerelease:true}))issues.push(name+' 的 '+peer+' 要求 '+range+'，目标 '+target)}}
  out({compatible:issues.length===0,issues});
 }
 else if(op==='offline-models'){
  const patches=rows(read(path.join(profile,'cordis.patch.yml')));const d=patches.findLast(r=>r.id==='agent-default-model')?.config??{};const r=patches.findLast(r=>r.id==='llm-deepseek')?.config??{};out({default:d,models:(r.models??[]).map(m=>({provider:'deepseek-official',id:m.id,name:m.name??m.id,contextWindow:m.contextWindow??r.defaultContextWindow??null,maxTokens:m.maxTokens??r.maxTokens??null,input:m.inputModalities??['text']}))});
 }
 else throw Error('未知辅助操作 '+op);
}catch(e){console.error(e.message);process.exitCode=1;}
