// S&H Agenda: service worker mínimo para poder instalarla como app (no guarda nada en caché)
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>{if(e.request.mode==='navigate')e.respondWith(fetch(e.request).catch(()=>new Response('Sin conexión',{status:503,headers:{'Content-Type':'text/plain; charset=utf-8'}})))});
