export function formatLiveEvent({at=new Date().toISOString(),event,taskId,detail}) {
  const parts = [`[${at}]`, event];
  if (taskId) parts.push(`task=${taskId}`);
  if (detail) parts.push(`detail=${detail}`);
  return parts.join(' ');
}

export function createLiveEmitter({enabled=process.env.AX_RUNTIME_LIVE_CONSOLE==='true', logger=console.log}={}) {
  return (event, payload={}) => {
    if (!enabled) return;
    logger(formatLiveEvent({at:new Date().toISOString(), event, ...payload}));
  };
}
