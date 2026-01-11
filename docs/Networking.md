# Kubernetes Networking en Detalle: De curl al Pod

## Introducción: El Caos de los Múltiples Mundos de Red

Cuando trabajas con Kubernetes en local usando Kind y Podman, hay **tres mundos de red completamente diferentes** que existen simultáneamente y deben comunicarse entre sí. Esto es lo que genera la confusión. No es una sola red—son capas que se traducen unas a otras continuamente.

En tu cluster:
- **Mundo 1**: Tu Mac (localhost)
- **Mundo 2**: Los contenedores Podman que contienen los nodos Kubernetes
- **Mundo 3**: La red overlay de Kubernetes (servicios, pods, etcd)

Cada uno tiene sus propios rangos de IP, y los paquetes deben transformarse constantemente mientras viajan entre mundos.

---

## Concepto 1: DNAT y la Traducción de Puertos

### ¿Qué es DNAT?

DNAT significa **Destination Network Address Translation** (Traducción de Dirección de Red Destino). Es un mecanismo del kernel Linux (iptables) que intercepta paquetes y **cambia el destino** antes de que lleguen al servicio final.

### Una Analogía: El Portero del Edificio

Imagina un edificio de oficinas:
- Alguien llama al buzón principal: "Quiero hablar con la oficina 800"
- El **portero** (iptables/kube-proxy) recibe la llamada
- El portero **no tiene oficina 800**, pero sabe que esa llamada es para "Recursos Humanos"
- Mira su **lista de extensiones** (iptables rules) y ve: "Oficina 800 → Ext. 2345"
- El portero **redirecciona la llamada** a la extension 2345

En tu cluster, esto funciona así:

```
1. Tu curl hace una llamada a: localhost:30080
2. iptables intercepta: "¿A dónde va esto?"
3. iptables mira la regla: "Puerto 30080 → Servicio Spink en puerto 80"
4. iptables mira nuevamente: "Servicio Spink puerto 80 → Pod en 10.244.1.2:8080"
5. El paquete llega a la dirección REAL: 10.244.1.2:8080
```

### Las Traslaciones en Tu Cluster Específico

Tu aplicación Spink hace este viaje:

```
┌──────────────────────────────────────────────────────────────┐
│ TRANSFORMACIONES DE IP:PUERTO                                │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│ 1. Inicio en tu Mac:                                         │
│    curl http://localhost:30080                               │
│    └─→ 127.0.0.1:30080                                       │
│                                                              │
│ 2. Entra a la red Podman (Kind expone el nodo control-plane) │
│    127.0.0.1:30080 → 172.18.0.2:30080                        │
│    (Kind mapping: localhost:30080 ↔ control-plane:30080)     │
│                                                              │
│ 3. El puerto 30080 entra al nodo Kubernetes (control-plane)  │
│    Los **iptables rules** redirigen a la ClusterIP:puerto    │
│    172.18.0.2:30080 → 10.96.244.84:80                        │
│    (Este es el Servicio: el "portero" que conoce clientes)   │
│                                                              │
│ 4. El servicio sabe dónde están los Pods en ese momento      │
│    10.96.244.84:80 → 10.244.1.2:8080 (ó 10.244.2.2:8080)     │
│    (Elegido al azar por kube-proxy entre los Endpoints)      │
│                                                              │
│ 5. FINALMENTE: llega al container                            │
│    Spring Boot escucha en 0.0.0.0:8080 y recibe la solicitud │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

Otra forma de explicarlo:

```
Tu petición: "Quiero puerto 30080"
    ↓ (iptables traduce)
Lo que el pod ve: "Alguien quiere puerto 8080"
```

```
Externo:  localhost:30080  ← Tú accedes aquí
    ↓ (Podman NAT)
Nodo:     172.18.0.2:30080  ← Entra al cluster
    ↓ (iptables + kube-proxy DNAT)
Service:  10.96.244.84:80   ← Traducción intermedia
    ↓ (otro DNAT)
Pod:      10.244.1.2:8080   ← ✅ Llega aquí
```

La magia: iptables traduce automáticamente toda esta cadena. El pod NO sabe que viniste de localhost:30080. Solo ve que alguien llegó a su puerto 8080.

### Por Qué Se Necesita DNAT

Sin DNAT, cuando el pod responde, no sabría cómo volver:
- El pod diría: "Mi IP es 10.244.1.2, respondo desde ahí"
- Pero tu Mac está en 127.0.0.1—**no puede comunicarse directamente** con 10.244.1.2
- DNAT **revierte** la transformación en la respuesta automáticamente
- El kernel recuerda: "Esa respuesta de 10.244.1.2 era para 127.0.0.1:30080"

Así funciona el **estado** en las conexiones TCP/UDP—iptables lo rastrea.

---

## Concepto 2: Los Tres Rangos de IP y Por Qué Todos Existen

### El Problema: ¿Por qué no una sola red?

En Kubernetes vanilla, hay un requisito fundamental: **cada pod debe tener una IP única y alcanzable desde todos los otros pods**. Pero también necesitas:
1. Estabilidad en los servicios (las IPs de pods son efímeras)
2. Aislamiento entre el host local y la red de pods
3. Compatibilidad con el runtime del contenedor (Podman)

Esto genera **tres capas de direccionamiento**:

### 1. Red Podman: 172.18.0.0/16 (El Mundo del Host)

**Rango**: 172.18.0.0/16

Esta es la red **virtual de Docker/Podman** en tu Mac. Cada contenedor que corre en Podman obtiene una IP aquí:

```
172.18.0.1  = Gateway Podman (puede acceder a tu Mac)
172.18.0.2  = control-plane node (el único expuesto a localhost:30080)
172.18.0.3  = worker-1 node
172.18.0.4  = worker-2 node
```

**Propósito**: Permite que tu Mac comunique con los nodos Kubernetes. Sin esta red, localhost:30080 no llegaría nunca al puerto en el nodo.

**Quién maneja esto**: Podman (el runtime de contenedores), no Kubernetes.

### 2. Red de Servicios Kubernetes: 10.96.0.0/12 (El Mundo de Servicios)

**Rango**: 10.96.0.0/12 (típicamente, se asignan direcciones en 10.96.x.x)

Esta es la red **virtual de Kubernetes** que existe solo dentro del cluster. No es una red física—es una **abstracción administrada por kube-proxy**.

```
10.96.0.1       = DNS Kubernetes (kube-dns)
10.96.0.10      = Kubernetes API Server (para kubectl)
10.96.244.84    = Tu Servicio "spink" (asignado automáticamente)
```

**Propósito**: 
- Proporcionar **IPs estables** para servicios (aunque los pods cambien)
- Actuar como **punto de entrada único** (load balancing)
- Funcionar como un **nivel de abstracción** sobre los pods volátiles

**Quién maneja esto**: kube-proxy crea reglas iptables para traducir estas IPs "virtuales" a pods reales.

**Importante**: Nadie puede hacer ping a 10.96.244.84 como si fuera una IP normal. Es una **dirección fantasma**—solo iptables sabe cómo manejarla.

### 3. Red de Pods (Overlay): 10.244.0.0/16 (El Mundo de los Pods)

**Rango**: 10.244.0.0/16

Esta es la red **real** donde viven los pods. Cada pod obtiene una IP única y **alcanzable** en esta red overlay (usando CNI, típicamente Flannel o Cilium en Kind):

```
10.244.0.0/24   = Ruta en control-plane (pero sin pods)
10.244.1.0/24   = Ruta en worker-1
  └─ 10.244.1.2 = Tu pod spink-xxx-yyyy en worker-1
10.244.2.0/24   = Ruta en worker-2
  └─ 10.244.2.2 = Tu pod spink-zzz-wwww en worker-2
```

**Propósito**:
- Proporcionar conectividad **real** entre pods
- Permitir que pods en **diferentes nodos** se comuniquen
- Ser la red **nativa** donde los contenedores realmente escuchan

**Quién maneja esto**: El CNI (Container Network Interface) implementa vxlan o tuneling para que paquetes entre 10.244.1.2 y 10.244.2.2 lleguen correctamente entre nodos.

### Diagrama de Los Tres Mundos

```
┌─────────────────────────────────────────────────────────────────┐
│ TU MAC (127.0.0.1)                                              │
├─────────────────────────────────────────────────────────────────┤
│  Tu shell: curl http://localhost:30080                          │
│  └──→ Paquete sale hacia afuera                                 │
│       (Podman port mapping captura esto)                        │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ RED PODMAN (172.18.0.0/16) - El "Host Virtual"                  │
│                                                                 │
│  172.18.0.2 (control-plane) ← El paquete llega aquí             │
│  172.18.0.3 (worker-1)                                          │
│  172.18.0.4 (worker-2)                                          │
│                                                                 │
│  iptables en control-plane maneja la redirección                │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ RED DE SERVICIOS K8S (10.96.0.0/12) - El "Directorio"           │
│ Es una capa de abstracción.                                     |
|                                                                 │
│  10.96.244.84 (ClusterIP del Servicio spink)                    │
│  │                                                              │
│  └─→ kube-proxy sabe que este servicio tiene dos Endpoints:     │
│      • 10.244.1.2:8080 (worker-1)                               │
│      • 10.244.2.2:8080 (worker-2)                               │
│                                                                 │
│  kube-proxy elige uno (round-robin, random, etc.)               │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ RED DE PODS (10.244.0.0/16) - El "Mundo Real"                   │
│                                                                 │
│  10.244.1.2 (spink pod en worker-1)                             │
│  │                                                              │
│  └─→ Spring Boot escucha en :8080                               │
│      ✓ Recibe el paquete                                        │
│      ✓ Procesa la solicitud                                     │
│      ✓ Envía respuesta                                          │
│      ✓ Todo se traduce de vuelta automáticamente                │
│                                                                 │
│  10.244.2.2 (spink pod en worker-2)                             │
└─────────────────────────────────────────────────────────────────┘
```

Analogía de la vida real:
```
Tu casa (127.0.0.1) → Dirección postal (172.18.0.2)
                    → Nombre de empresa (spink - el Service)
                    → Oficina específica (10.244.1.2:8080)
```

Tú conoces el nombre de la empresa ("spink"), pero la empresa tiene una oficina específica. Cuando llamas, la recepcionista (kube-proxy) te enruta a la oficina correcta.

---

## Concepto 3: Cómo el Sistema Enruta Tu Solicitud

### El Flujo Paso a Paso

Cuando ejecutas `curl http://localhost:30080`, aquí está exactamente qué sucede en tu cluster:

#### PASO 1: El Paquete Sale desde tu Mac

```
curl → localhost:30080
```

Tu terminal es una app normal. No sabe nada de Kubernetes. Solo dice:
- "Voy a TCP connect a 127.0.0.1:30080"

#### PASO 2: Podman Intercepta (Port Mapping)

En tu `kind/kind-cluster.yaml` hay:

```yaml
extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
```

**Qué significa**: "Todo lo que llega a [Podman Host]:30080 redirige a [control-plane container]:30080"

En Podman (que corre en tu Mac):
```
localhost:30080 (Mac) --[NAT por Podman]--> 172.18.0.2:30080 (control-plane)
```

El paquete ahora tiene:
- Source: 127.0.0.1 (tu Mac)
- Dest: **172.18.0.2:30080** (dentro de la red Podman)

#### PASO 3: El Paquete Entra en el Nodo Kubernetes

Llega a `kubelet` (el agent de Kubernetes en el nodo). El nodo vé:
- "Un paquete a puerto 30080 llegó a mi IP de nodo"
- "¿Qué servicio escucha en 30080?"

El kernel Linux en el nodo consulta la **tabla de iptables**:

```
IF puerto = 30080
  THEN consulta kube-proxy
  
kube-proxy dice:
  "El puerto 30080 corresponde al Service 'spink'"
  
Service 'spink' tiene label selector: app=spink
  
Kubernetes busca todos los pods con label app=spink:
  ✅ Pod 1: 10.244.1.2 (worker-1)
  ✅ Pod 2: 10.244.2.2 (worker-2)
  
kube-proxy elige uno (round-robin):
  → Selecciona: 10.244.1.2
```

#### PASO 4: kube-proxy ha preparado todo

**Antes de que tu solicitud llegue**, kube-proxy ya ha:

1. **Visto** el Servicio spink en etcd
2. **Visto** los Endpoints (qué pods implementan spink)
3. **Creado reglas iptables** que dicen:

```
iptables rule para puerto 30080 →
  └─ Redirige a ClusterIP 10.96.244.84:80
     └─ Redirige a uno de los endpoints:
        ├─ 10.244.1.2:8080 (Pod en worker-1)
        └─ 10.244.2.2:8080 (Pod en worker-2)
```

Cuando tu paquete llega a 30080, **iptables lo transforma**:

```
Origen: 127.0.0.1
Destino: 172.18.0.2:30080
    ↓↓↓ (iptables DNAT)
Origen: 127.0.0.1 (registrado en estado)
Destino: 10.244.1.2:8080 (ó 10.244.2.2:8080)
```
```
DNAT (traducción) y envío
Paquete ORIGINAL:
  SRC = 127.0.0.1
  DST = 172.18.0.2:30080
  
iptables TRANSFORMA:
  SRC = 127.0.0.1 (sin cambiar)
  DST = 10.244.1.2:8080 ← CAMBIADO
  
CNI (flannel) enruta el paquete:
  "10.244.1.2 está en worker-1, envío por vxlan"
  
Pod recibe:
  SRC = 127.0.0.1
  DST = 10.244.1.2:8080 ✅
  Spring Boot lo procesa
```

El "motor" detrás de todo esto es:
```
┌──────────────────┐
│    iptables      │  ← Reglas de traducción
│  (kernel Linux)  │
└────────┬─────────┘
         ↓
┌──────────────────┐
│  kube-proxy      │  ← Administra las reglas
│  (daemon K8s)    │  ← Consulta etcd para endpoints
└────────┬─────────┘
         ↓
┌──────────────────┐
│  etcd (K8s DB)   │  ← Almacena qué pods existen
│                  │  ← Y en qué nodos están
└──────────────────┘
```

El flujo:

1. kube-proxy monitorea constantemente etcd
2. Cuando un pod nace o muere, etcd se actualiza
3. kube-proxy automáticamente actualiza las reglas iptables
4. iptables aplica la nueva regla al kernel


#### PASO 5: El CNI Enruta por la Red Overlay

El paquete está ahora dirigido a 10.244.1.2 (una IP en worker-1).

Pero **espera**—el paquete está **físicamente en el control-plane**, no en worker-1.

El CNI (Container Network Interface) hace su magia:
- Ve: "Destino 10.244.1.x, pero estoy en control-plane"
- Mira su tabla de rutas: "10.244.1.0/24 → vxlan tunel a worker-1"
- Encapsula el paquete en un tunel vxlan
- Lo envía a worker-1

En worker-1:
- El CNI desencapsula el paquete
- Ahora la IP destino 10.244.1.2 es **local** en worker-1
- Enruta normalmente a esa IP

#### PASO 6: El Paquete Llega al Contenedor

En worker-1, hay un puente de red (docker0 o similar):
- El paquete destino 10.244.1.2:8080 se entrega al contenedor
- El contenedor es tu pod spink
- Dentro: Spring Boot escucha en 0.0.0.0:8080

Spring Boot:
```
✓ Recibe la solicitud GET / (ó lo que sea)
✓ Ejecuta tu código Java
✓ Genera una respuesta (HTTP 200 OK, HTML, JSON, etc.)
✓ Envía la respuesta de vuelta
```

#### PASO 7: La Respuesta Regresa (Automáticamente)

El pod responde. El paquete de respuesta:

```
Origen: 10.244.1.2:8080 (el pod)
Destino: 127.0.0.1:30080 (tu Mac)
```

Aquí es donde **iptables en modo stateful** es crucial:

- iptables vé que esta respuesta viene de 10.244.1.2:8080
- Pero **RECUERDA** que esta conexión fue DNAT-izada al revés
- Revierte automáticamente:

```
Origen: 10.244.1.2:8080 → 172.18.0.2:30080
Destino: 127.0.0.1:30080 → 127.0.0.1:PUERTO_EFÍMERO
```

El paquete vuelve a través del tunel CNI, luego de vuelta a Podman, luego a tu Mac.

Tu `curl` recibe la respuesta. **Fin del viaje.**

---

## Concepto 4: iptables y kube-proxy - El Ecosistema de Enrutamiento

### ¿Qué es kube-proxy?

`kube-proxy` es un **demonio de Kubernetes** que corre en **cada nodo**. Su único trabajo es:

> Mantener iptables actualizado para que los servicios virtuales funcionen.

### ¿Por Qué No Simplemente Hacer un Load Balancer?

Podrían haber creado un "servidor de proxy" que simplemente recibiera tráfico y lo reenviara. Pero eso sería lento:
- Cada paquete tendría que atravesar userspace (el programa proxy)
- Mucho overhead de CPU
- Latencia innecesaria

En cambio, **iptables es kernel-space**:
- Cada paquete es interceptado a nivel de kernel
- Transformación sucede en nanosegundos
- Escala a millones de conexiones sin sudor

### Cómo Funciona kube-proxy

#### 1. kube-proxy Observa etcd

```
etcd (base de datos Kubernetes)
  ├─ Servicios (metadata)
  └─ Endpoints (qué pods implementan cada servicio)
```

`kube-proxy` usa el API de Kubernetes para **observar cambios**:

```
"El Servicio spink existe"
"Sus puertos mapeados son: 80 → 8080"
"Sus endpoints son actualmente: 10.244.1.2, 10.244.2.2"
```

#### 2. kube-proxy Genera Reglas iptables

Para **cada servicio**, crea una cadena (chain) de iptables:

```bash
# Pseudocódigo simplificado de lo que hace:

# 1. "Si el destino es MI_IP (172.18.0.2) puerto 30080:"
iptables -A PREROUTING -d 172.18.0.2 -p tcp --dport 30080 \
  -j KUBE_SVC_SPINK

# 2. "Luego enruta a un endpoint aleatorio:"
iptables -A KUBE_SVC_SPINK -j KUBE_SEP_SPINK_1  # 10.244.1.2:8080
iptables -A KUBE_SVC_SPINK -j KUBE_SEP_SPINK_2  # 10.244.2.2:8080
# (Probabilidad 50/50 para cada uno)

# 3. "Realiza el DNAT al endpoint elegido:"
iptables -A KUBE_SEP_SPINK_1 -j DNAT \
  --to-destination 10.244.1.2:8080
```

#### 3. El Flujo de Tráfico en iptables

```
Paquete llega → :30080
    ↓
PREROUTING chain (filtros básicos)
    ↓
¿Es para un Servicio K8s? → Sí
    ↓
KUBE_SVC_SPINK chain
    ↓
¿Cuál endpoint? (Probabilities 50% / 50%)
    ├─ KUBE_SEP_SPINK_1 → 10.244.1.2:8080
    └─ KUBE_SEP_SPINK_2 → 10.244.2.2:8080
    ↓
DNAT (Reescribe direcciones)
    ↓
Enrutamiento normal (¿Cómo llego a 10.244.1.2?)
    ↓
CNI (vxlan si es en otro nodo)
    ↓
Entrega al contenedor
```

#### 4. Qué Pasa Cuando Cambian las Cosas

Si un pod **muere o nace**, etcd se actualiza:

```
etcd cambió:
  "10.244.1.2 ya no existe"
  "Ahora tenemos 10.244.2.2 y 10.244.3.2"

↓

kube-proxy lo ve (watcher en etcd)

↓

Actualiza las reglas iptables:
  KUBE_SEP_SPINK_1 → 10.244.2.2:8080 (cambió!)
  KUBE_SEP_SPINK_2 → 10.244.3.2:8080 (cambió!)

↓

Las próximas conexiones entrantes
usan los nuevos endpoints automáticamente
(Las conexiones existentes siguen en los endpoints viejos,
hasta que se cierren)
```

### Modes de kube-proxy

`kube-proxy` puede operar en **3 modos**:

1. **userspace** (antiguo, lento)
   - Todos los paquetes pasan por un proxy program
   - Requiere context switches kernel ↔ userspace
   - Deprecated en Kubernetes moderno

2. **iptables** (estándar, eficiente)
   - iptables maneja todo
   - Kernel-space
   - Puede tener problemas con conexiones muy largas (es stateless por defecto)
   - **Tu cluster probablemente usa esto**

3. **ipvs** (avanzado, escalable)
   - Usa el módulo IPVS del kernel
   - Más eficiente que iptables a muy gran escala
   - Require módulos especiales del kernel

En Kind típicamente se usa **iptables**.

### Ver las Reglas iptables en Vivo

Si entras en un nodo, puedes inspeccionar:

```bash
# Entrar al nodo control-plane
kubectl debug node/control-plane -it --image=ubuntu

# Dentro:
iptables -L -n -v -t nat | grep spink

# Verás líneas como:
# Chain KUBE_SVC_SPINK (2 references)
# target  prot opt in  out  source  destination
# KUBE_SEP_SPINK_1  all  --  *  *  0.0.0.0/0  0.0.0.0/0  /* spink */
# KUBE_SEP_SPINK_2  all  --  *  *  0.0.0.0/0  0.0.0.0/0  /* spink */
```

Algunas notas adicionales sobre kube-proxy: 

kube-proxy es un programa de Kubernetes que:

1. Monitorea etcd (la base de datos de K8s)
2. Detecta cambios (nuevos pods, servicios eliminados, etc.)
3. Actualiza las reglas de iptables automáticamente
4. Mantiene todo sincronizado

El ciclo de vida: 

```
1. Despliegas un pod:
   kubectl apply -f deployment.yaml
   
2. Kubernetes lo crea en etcd:
   Pod: spink-7dc95bf986-485xb
   IP: 10.244.1.2
   Label: app=spink
   
3. kube-proxy lo detecta:
   "Hay un nuevo pod con label app=spink"
   "Pertenece al Service spink"
   
4. kube-proxy actualiza iptables:
   iptables -t nat -A KUBE-SEP-XXXXX \
     -p tcp -m tcp --dport 8080 \
     -j DNAT --to-destination 10.244.1.2:8080
   
5. El sistema está listo:
   ✅ Las peticiones al puerto 30080 ahora pueden encontrar al pod
```

kube-proxy vs iptables:

```
kube-proxy                    iptables
(Inteligencia)               (Ejecución)

Sabe DÓNDE están            Aplica las reglas
los pods (etcd)             al kernel Linux

Sabe QUÉ servicios          Traduce IPs y puertos
existen                      en tiempo real

Crea las reglas             Procesa MILLONES
cada vez que hay             de paquetes por
cambios                      segundo
```

---

## El Viaje Completo: De Inicio a Fin

Ahora, uniendo todo:

### Estado Inicial

Tu cluster ha sido creado con Kind:

```yaml
# kind-cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
extraPortMappings:
  - containerPort: 30080
    hostPort: 30080  # ← Tu Mac localhost:30080 mapea aquí
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 30080
  - role: worker
  - role: worker
```

Se crea:
- 3 contenedores Podman: control-plane, worker-1, worker-2
- Red Podman 172.18.0.0/16 entre ellos
- CNI (Flannel/Cilium) con redes 10.244.0.0/16
- `kubelet` en cada nodo

### El Servicio NodePort

```yaml
# service-nodeport.yaml
apiVersion: v1
kind: Service
metadata:
  name: spink
spec:
  type: NodePort
  selector:
    app: spink
  ports:
    - port: 80           # Puerto dentro del cluster (ClusterIP)
      targetPort: 8080   # Puerto en el contenedor
      nodePort: 30080    # Puerto en CADA nodo (accesible externamente)
```

`kube-proxy` lo ve y crea reglas iptables automáticamente.

### El Deployment

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spink
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spink
  template:
    metadata:
      labels:
        app: spink
    spec:
      containers:
        - name: spink
          image: localhost/spink:1.0.1
          ports:
            - containerPort: 8080
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
```

Kubernetes:
1. Crea 2 pods basados en esta especificación
2. Cada pod obtiene una IP del rango 10.244.x.x
3. Actualiza el Endpoint del Servicio spink con las IPs de pods

### El Momento de la Verdad: `curl http://localhost:30080`

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. TU MAC - Ejecución del comando                               │
├─────────────────────────────────────────────────────────────────┤
│ $ curl http://localhost:30080                                   │
│   └─→ TCP SYN packet a 127.0.0.1:30080                          │
│   └─→ Espera conexión establecida                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 2. PODMAN - Port Mapping                                        │
├─────────────────────────────────────────────────────────────────┤
│ Podman vé: packet a 127.0.0.1:30080                             │
│ Aplica su NAT:                                                  │
│ 127.0.0.1:30080 ──NAT──> 172.18.0.2:30080                       │
│ (source port podría cambiar también, Podman lo rastrea)         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 3. CONTROL-PLANE NODE (172.18.0.2) - Recibe paquete             │
├─────────────────────────────────────────────────────────────────┤
│ Paquete llega a puerto 30080                                    │
│                                                                 │
│ Kernel consulta: ¿Quién escucha en :30080?                      │
│   ✓ kubelet (la aplicación del nodo) responde                   │
│                                                                 │
│ kubelet consulta netfilter (iptables):                          │
│   "¿Hay una regla para puerto 30080?"                           │
│   ✓ Sí! PREROUTING chain                                        │
│                                                                 │
│ iptables aplica DNAT:                                           │
│   Original:  172.18.0.2:30080                                   │
│   → Destino: 10.244.1.2:8080 (ó 10.244.2.2:8080)                │
│                                                                 │
│ El paquete se marca como "DNAT tracked"                         │
│ (iptables lo seguirá para la respuesta)                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 4. ENRUTAMIENTO NORMAL - ¿Cómo llego a 10.244.1.2?              │
├─────────────────────────────────────────────────────────────────┤
│ Kernel mira tabla de rutas:                                     │
│ $ route -n | grep 10.244.1                                      │
│ 10.244.1.0/24 dev cni0 scope link                               │
│                                                                 │
│ ¿cni0? Es una interfaz virtual creada por el CNI                │
│                                                                 │
│ Si destino es local (cni0):                                     │
│   ✓ Enruta directamente                                         │
│                                                                 │
│ Si destino NO es local (en otro worker):                        │
│   ✓ CNI enruta vía vxlan tunnel                                 │
│   ✓ Encapsula paquete y lo envía a ese worker                   │
│   ✓ El worker desencapsula y entrega localmente                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 5. CONTENEDOR - Spring Boot                                     │
├─────────────────────────────────────────────────────────────────┤
│ Paquete llega a puente docker/cni dentro del nodo               │
│ Se entrega al contenedor (namespace de red del pod)             │
│                                                                 │
│ Spring Boot:                                                    │
│   ```                                                           │
│   // Spring Boot escucha en 0.0.0.0:8080                        │
│   public static void main(String[] args) {                      │
│       SpringApplication.run(ContainersApplication.class,        │
│           args);                                                │
│   }                                                             │
│   ```                                                           │
│                                                                 │
│   ✓ Recibe GET / (ó POST /api/data, etc.)                       │
│   ✓ Procesa con controladores Spring MVC                        │
│   ✓ Genera respuesta (HTTP 200, HTML, JSON)                     │
│   ✓ Envía el paquete de respuesta                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ 6. RESPUESTA - Vuelve por el Mismo Camino (Automáticamente)     │
├─────────────────────────────────────────────────────────────────┤
│ Pod envía respuesta con:                                        │
│   Origen: 10.244.1.2:8080                                       │
│   Destino: 127.0.0.1:EPHEMERAL_PORT                             │
│                                                                 │
│ iptables (tabla POSTROUTING):                                   │
│   "Reconozco esta respuesta"                                    │
│   "La redirecciono de vuelta a 172.18.0.2:30080"                │
│   (El state tracking recuerda la conexión original)             │ 
│                                                                 │
│ La respuesta:                                                   │
│   ✓ Vuelve por vxlan si es de otro worker                       │
│   ✓ Podman aplica su NAT inverso                                │
│   ✓ Llega a 127.0.0.1:30080                                     │
│                                                                 │
│ curl recibe la respuesta                                        │
│ $ curl http://localhost:30080                                   │
│ > 200 OK                                                        │
│ > (respuesta de Spring Boot)                                    │
└─────────────────────────────────────────────────────────────────┘
```

STARTUP de kube-proxy
```
STARTUP (antes de que llegue tu curl):

1. kube-proxy inicia en cada nodo
   └─ Se conecta a API de Kubernetes (etcd)
   └─ Observa (watches) cambios en:
      • Services (busca nueva Service spink)
      • Endpoints (busca qué pods implementan spink)

2. kube-proxy VE en etcd:
   "Hay un Service: spink
    ClusterIP: 10.96.244.84
    Puerto: 80
    NodePort: 30080
    Endpoints: 10.244.1.2:8080, 10.244.2.2:8080"

3. kube-proxy GENERA reglas iptables ESTÁTICAS:
   iptables -A KUBE-NODEPORTS -p tcp --dport 30080 \
     -j KUBE-SVC-66BRF57DTBANX7J2
   
   iptables -A KUBE-SVC-66BRF57DTBANX7J2 \
     -j KUBE-SEP-BRTKNB33 (50% probabilidad → 10.244.1.2:8080)
   
   iptables -A KUBE-SVC-66BRF57DTBANX7J2 \
     -j KUBE-SEP-2UT73H (50% probabilidad → 10.244.2.2:8080)
   
   iptables -A KUBE-SEP-BRTKNB33 -j DNAT --to 10.244.1.2:8080
   iptables -A KUBE-SEP-2UT73H -j DNAT --to 10.244.2.2:8080

4. kube-proxy "se sienta" y espera
   └─ Observa etcd por cambios (si un pod muere/nace)
   └─ Si hay cambio, actualiza las reglas
```

Diagrama más sencillo: 

```
1. Tu Mac: curl http://localhost:30080
   └─ Paquete: SRC=127.0.0.1, DST=127.0.0.1:30080

2. Podman redirige:
   └─ Paquete: SRC=127.0.0.1, DST=172.18.0.2:30080

3. Paquete: SRC=127.0.0.1, DST=172.18.0.2:30080 (del Podman)

4. PRIMER DNAT (NodePort → ClusterIP)
   └─ El KERNEL consulta las reglas (que kube-proxy preparó)
   └─ Ejecuta: -j KUBE-NODEPORTS → -j KUBE-SVC-66BRF57DTBANX7J2
   └─ iptables traduce: 172.18.0.2:30080 → 10.96.244.84:80
   └─ **← kube-proxy NO está aquí. Ya se fue. Las reglas hacen el trabajo.**

5. SEGUNDO DNAT (ClusterIP → Endpoint real)
   └─ Elige endpoint (50/50): KUBE-SEP-BRTKNB33 o KUBE-SEP-2UT73H
   └─ iptables traduce: 10.96.244.84:80 → 10.244.1.2:8080
   └─ **← Nuevamente: kube-proxy NO está aquí. iptables ejecuta la regla.**

6. CNI (flannel) enruta:
   └─ "10.244.1.2 está en worker-1"
   └─ Envía a través de vxlan

7. Pod recibe:
   └─ Spring Boot en 0.0.0.0:8080
   └─ Procesa /actuator/health
   └─ Responde: "Health: UP"

8. Respuesta vuelve:
   └─ Mismo camino, pero reversed
   └─ Llega a tu Mac
```

### Lo Que Sucede en Los Milisegundos

```
Tiempo:     Evento:
T+0ms       curl → localhost:30080
T+0.1ms     Podman NAT: 127.0.0.1 → 172.18.0.2
T+0.2ms     Paquete llega a control-plane:30080
T+0.3ms     iptables DNAT: :30080 → 10.244.1.2:8080
T+0.4ms     Enrutamiento kernel: ¿Local o vxlan?
            (supongamos local en control-plane)
T+0.5ms     Paquete entregado al contenedor
T+1.0ms     Spring Boot recibe, procesa
            (el tiempo varía mucho aquí)
T+5.0ms     Spring Boot genera respuesta
T+5.1ms     Respuesta enviada (origen: 10.244.1.2)
T+5.2ms     iptables DNAT inverso (POSTROUTING)
T+5.3ms     Podman NAT inverso
T+5.4ms     Respuesta llega a 127.0.0.1:30080
T+5.5ms     curl recibe y cierra conexión
```

En la práctica, todo esto sucede en **5-100ms** dependiendo de cuánto trabajo haga Spring Boot.

---

## Casos Especiales y Preguntas Frecuentes

### P: ¿Por Qué NodePort en 30080 y No Algún Puerto < 1024?

Los puertos 0-1023 requieren permisos de root en Unix. NodePort típicamente mapea a 30000-32767 para evitar conflictos. El port 30080 es arbitrario.

### P: ¿Qué Pasa Si Ambos Pods Mueren?

```
1. Kubelet lo detecta (healthcheck cada 10s)
2. Actualiza el Endpoint del Servicio (elimina ambas IPs)
3. kube-proxy lo ve y actualiza iptables
4. Las nuevas solicitudes entrantes:
   - Llegan a :30080
   - iptables intenta DNAT
   - Pero no hay endpoints... 
   - Conexión rechazada (connection refused)
5. kubectl create new pods (si Deployment lo permite)
6. Cuando hay pods, el Endpoint se actualiza
7. El tráfico se enruta automáticamente
```

### P: ¿Cómo Sabemos Que Fue a Worker-1 y No Worker-2?

No lo sabes sin inspeccionar. kube-proxy elige aleatoriamente (o round-robin depende del modo). Puedes:

```bash
# Hacer múltiples requests y ver qué pod responde
for i in {1..10}; do
  curl -s http://localhost:30080 | grep hostname
done

# Verás saltar entre spink-xxxx-1 y spink-yyyy-2
```

### P: ¿Por Qué El Paquete No Se Pierde Cruzando Redes?

Porque **cada transformación de red es reversible y stateful**:

1. **Podman NAT**: Registra la conexión. Cuando ve la respuesta con esos números, revierte.
2. **iptables DNAT**: El kernel rastrea el estado (conntrack). Recuerda qué DNAT hizo.
3. **CNI vxlan**: Los túneles encapsulan en ambas direcciones.

Si alguna parte fallara, la conexión se cortaría (timeout o reset).

### P: ¿Qué Pasa Con Conexiones Persistentes (WebSocket)?

El flujo es el mismo, pero la conexión **persiste**:

```
1. curl hace TCP CONNECT a :30080
2. Pasa por DNAT una sola vez
3. iptables mantiene la conexión en su tabla conntrack
4. Datos fluyen bidireccionalmente dentro de esa conexión
5. Cada dato usa el mismo DNAT que se estableció al inicio
6. Cuando cierra, conntrack limpia la entrada
```

WebSockets, SSH, cualquier protocolo que necesite conexión persistente funciona porque **iptables recuerda** el estado.

---

## Resumen: Los Cuatro Pilares del Networking en Kubernetes

| Concepto | Propósito | Tecnología | Ejemplo en Tu Cluster |
|----------|-----------|-----------|----------------------|
| **DNAT** | Traducir puertos/IPs para que tráfico se enrute correctamente | iptables (kernel) | 127.0.0.1:30080 → 172.18.0.2:30080 → 10.96.244.84:80 → 10.244.1.2:8080 |
| **3 Rangos de IP** | Separar responsabilidades (Host, Servicios, Pods) | Red Podman + K8s CNI | 172.18.0.0/16 (Podman) + 10.96.0.0/12 (Servicios) + 10.244.0.0/16 (Pods) |
| **Enrutamiento** | Encontrar el camino entre redes | iptables + CNI vxlan + kernel routes | Determinar: ¿Pod local? ¿En otro worker? ¿Cómo llego? |
| **kube-proxy + iptables** | Hacer que los servicios virtuales funcionen | kube-proxy daemon + iptables rules | kube-proxy crea iptables → DNAT a pods → Automáticamente equilibra carga |

---

## Comandos Útiles Para Inspeccionar

```bash
# Ver servicios y ClusterIPs
kubectl get svc -A

# Ver endpoints reales de un servicio
kubectl get endpoints spink -o wide

# Ver pods y sus IPs
kubectl get pods -A -o wide

# Entrar a un nodo y ver iptables
kubectl debug node/control-plane -it --image=ubuntu
  # dentro:
  apt update && apt install -y iptables
  iptables -L -t nat -n | grep spink

# Ver logs de kube-proxy
kubectl logs -n kube-system -l component=kube-proxy

# Hacer una solicitud desde dentro del cluster a un servicio
kubectl run -it --rm debug --image=ubuntu --restart=Never -- bash
  apt update && apt install -y curl
  curl http://spink.default:80
  curl http://10.96.244.84:80  # Acceso directo a ClusterIP

# Ver rutas de red en un nodo
kubectl debug node/worker-1 -it --image=ubuntu
  route -n
  # Verás: 10.244.0.0/24 dev cni0, 10.244.2.0/24 via 172.18.0.4 (tuneling)
```

---

## Conclusión

El networking en Kubernetes es **complejo** pero **lógico**. Lo que sucede es:

1. **DNAT traduce** puertos y IPs
2. **Tres redes coexisten** con propósitos específicos
3. **El enrutamiento es automático** gracias a CNI y iptables
4. **kube-proxy mantiene todo actualizado** observando etcd

La "magia" es en realidad **ingeniería sólida**: cada componente tiene un trabajo específico, y juntos crean un sistema que:
- Es eficiente (kernel-space, no proxies lentos)
- Es escalable (millones de conexiones simultáneas)
- Es tolerante a fallos (actualizaciones dinámicas sin interrupciones)
- Es transparente (abstracciones que se manejan automáticamente)

Ahora, cuando ejecutas `curl http://localhost:30080` y ves una respuesta, **sabes exactamente qué sucedió en los milisegundos intermedios**. 🎯
