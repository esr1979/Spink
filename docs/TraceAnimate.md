# Kubernetes Networking explicado con trazas reales

Este repositorio incluye el comando `make trace-animate`, cuyo objetivo es **enseñar de forma visual y basada en datos reales** cómo viaja una petición de red dentro de Kubernetes.

No es una simulación.  
No es teoría.  
Son **IPs reales, reglas reales e iptables reales**.

---

## Objetivo

Entender exactamente qué ocurre cuando ejecutas:

```bash
curl http://localhost:30080
```

Y cómo esa petición acaba llegando a una aplicación que escucha en el puerto 8080 dentro de un Pod.

## 📦 Datos reales del entorno

Ejemplo real obtenido dinámicamente del cluster:

| Elemento     | Valor real                    |
|--------------|-------------------------------|
| Pod          | spink-7dc95bf986-l6lqk        |
| IP del Pod   | 10.244.2.2                    |
| Nodo         | ink-cluster-worker2           |
| NodePort     | 30080                         |
| ClusterIP    | 10.96.153.212                 |
| Puerto app   | 8080                          |

---

## 🎯 Dónde escucha realmente la aplicación

La aplicación **solo escucha realmente aquí**:

```bash
10.244.2.2:8080
```

Todo lo demás (NodePort, ClusterIP, localhost:30080, etc.)
son redirecciones creadas mediante reglas de red (iptables / kube-proxy).

## 💡 Idea clave

Un **Service de Kubernetes**:

- ❌ No es un proceso  
- ❌ No escucha en ningún puerto  
- ✅ Es simplemente un conjunto de reglas de red (iptables)  

El componente **kube-proxy** instala reglas como esta en los nodos:

```bash
DNAT --to-destination 10.244.2.2:8080
```

Que significa literalmente:
"Cambia el destino del paquete para que vaya al Pod real"

## 🤔 ¿Por qué existen tres puertos distintos?
Service típico en Kubernetes:

```bash
ports:
- nodePort: 30080
  port: 80
  targetPort: 8080
```

| Nivel            | Puerto | Explicación |
|------------------|--------|--------------|
| Cliente externo   | 30080  | Puerto expuesto por el nodo (NodePort) |
| Service (virtual) | 80     | Puerto lógico interno del Service |
| Pod real          | 8080   | Puerto donde escucha realmente la app |


👉 El único puerto real es 8080.
Los demás son simplemente niveles de redirección creados por Kubernetes.

## Ruta real del paquete

Cuando haces:

```bash
curl http://localhost:30080
```

El recorrido real es:

```bash
[Tu Mac]
127.0.0.1:PUERTO_EFIMERO
        │
        ▼
[Podman redirección de puerto]
localhost:30080
        │
        ▼
[Nodo kind]
iptables (KUBE-NODEPORTS)
        │
        ▼
[Service spink]
10.96.153.212:80 (IP virtual)
        │
iptables (KUBE-SVC / KUBE-SEP)
        ▼
[Pod real]
10.244.2.2:8080  ← aquí vive Spring Boot
```

## make trace-animate

El comando:

```bash
make trace-animate
```

Hace lo siguiente:

- Descubre automáticamente:
  - Pod real
  - IP del Pod
  - Nodo
  - NodePort
  - ClusterIP
- Extrae reglas reales de iptables relacionadas con el Service.
- Muestra una traza paso a paso explicando cómo fluye un paquete real.
- Su objetivo es **pedagógico**, no solo técnico.

---

## ¿Qué enseña realmente este proyecto?

Este repositorio sirve para comprender:

- Cómo funcionan los NodePort
- Qué es realmente un Service
- Qué hace kube-proxy
- Cómo funciona DNAT con iptables
- Cómo viajan paquetes reales dentro del cluster
- Cómo preparar el terreno para entender Ingress
