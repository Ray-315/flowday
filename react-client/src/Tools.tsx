import { useEffect, useRef, type ReactNode } from 'react';
import { X } from './icons';
import { isTauri } from '@tauri-apps/api/core';

export function ToolsDialog({ title, onClose, children }: {title:string;onClose:()=>void;children:ReactNode}) {
  const ref=useRef<HTMLDialogElement>(null);
  useEffect(()=>{ const dialog=ref.current!; const opener=document.activeElement; dialog.showModal(); return()=>{dialog.close();if(opener instanceof HTMLElement && opener.isConnected) opener.focus();};},[]);
  return <dialog ref={ref} className="editor-dialog tools-dialog" aria-label={title} onCancel={event=>{event.preventDefault();onClose();}}>
    <div className="dialog-header"><h2>{title}</h2><button className="icon-button" aria-label="关闭" onClick={onClose}><X size={19}/></button></div>
    <div className="tools-body">{children}</div>
  </dialog>;
}
export async function exportFile(name:string, content:Blob|string) {
  if(isTauri()) {
    const {save}=await import('@tauri-apps/plugin-dialog');
    const fs=await import('@tauri-apps/plugin-fs');
    const path=await save({defaultPath:name});
    if(path) {if(typeof content==='string') await fs.writeTextFile(path,content); else await fs.writeFile(path,new Uint8Array(await content.arrayBuffer()));}
  } else {
    const url=URL.createObjectURL(typeof content==='string'?new Blob([content],{type:'application/octet-stream'}):content);
    const anchor=document.createElement('a');anchor.href=url;anchor.download=name;anchor.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
}
