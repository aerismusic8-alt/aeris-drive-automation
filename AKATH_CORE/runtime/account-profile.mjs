import fs from 'node:fs';
import os from 'node:os';
import {spawnSync} from 'node:child_process';
export function profilePath(){ return process.env.AX_ACCOUNT_PROFILE || os.homedir()+'\\.aeris\\account-profile.json'; }
export function loadAccountProfile(){
 const p=profilePath(); if(!fs.existsSync(p)) throw new Error('ACCOUNT_PROFILE_NOT_CONFIGURED');
 const raw=JSON.parse(fs.readFileSync(p,'utf8')); if(!raw.email||!raw.password_dpapi) throw new Error('ACCOUNT_PROFILE_INCOMPLETE');
 const enc=String(raw.password_dpapi).replaceAll("'","''");
 const ps="$s=ConvertTo-SecureString '"+enc+"';$b=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($s);try{[Runtime.InteropServices.Marshal]::PtrToStringBSTR($b)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)}";
 const r=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',ps],{encoding:'utf8',windowsHide:true});
 if(r.status!==0) throw new Error('ACCOUNT_PROFILE_DECRYPT_FAILED');
 return {...raw,password:r.stdout.trim()};
}