// S&H Agenda: instalación como app + avisos al celular (notificaciones push). No guarda nada en caché.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>{if(e.request.mode==='navigate')e.respondWith(fetch(e.request).catch(()=>new Response('Sin conexión',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}})))});
self.addEventListener('push',e=>{
  let d={};try{d=e.data?e.data.json():{}}catch(_){d={title:'S&H Agenda',body:e.data?e.data.text():''}}
  e.waitUntil((async()=>{
    const cs=await clients.matchAll({type:'window',includeUncontrolled:true});
    if(cs.some(c=>c.visibilityState==='visible'&&c.focused))return; // la agenda está abierta: ya suena sola
    await self.registration.showNotification(d.title||'S&H Agenda',{body:d.body||'',icon:'icon-192.png',badge:'icon-192.png',tag:d.tag||'sh',renotify:true,vibrate:[120,80,120],data:{url:'./agenda.html'}});
  })());
});
self.addEventListener('notificationclick',e=>{
  e.notification.close();
  e.waitUntil((async()=>{
    const cs=await clients.matchAll({type:'window',includeUncontrolled:true});
    for(const c of cs){if('focus' in c)return c.focus()}
    return clients.openWindow((e.notification.data&&e.notification.data.url)||'./agenda.html');
  })());
});
