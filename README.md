# Flask + MongoDB Deployment on Kubernetes (Minikube)

This project demonstrates the deployment of a Python Flask application connected to a MongoDB database on a local Kubernetes cluster using Minikube. The setup showcases containerization, Kubernetes deployments, persistent storage, service-based communication, and autoscaling.

---

## Tech Stack

- **Python (Flask)** - Web application framework
- **MongoDB** - NoSQL database
- **Docker** - Containerization platform
- **Kubernetes (Minikube)** - Container orchestration

---

## Prerequisites

Ensure the following are installed:

- Docker (v20.10 or later)
- Minikube (v1.25 or later)
- kubectl (v1.23 or later)
- Python 3.8+

Verify installations:
```bash
docker --version
minikube version
kubectl version --client
```

---

## Application Overview

The Flask application exposes REST endpoints and stores data in MongoDB.

### Endpoints

- **`/`** - Returns a welcome message with the current server timestamp
- **`/data`**
  - **POST**: Inserts JSON data into MongoDB
  - **GET**: Retrieves all stored data from MongoDB
- **`/health`** - Health check endpoint for liveness/readiness probes

---

## Docker Setup

### Dockerfile Overview

The Dockerfile uses Python 3.9-slim base image, installs dependencies from requirements.txt, copies the application code, and exposes port 5000.

### Build and Push Docker Image

```bash
# Build the image
docker build -t ayushgoyal24/flask-mongo-app:latest .

# Login to Docker Hub
docker login

# Push to Docker Hub
docker push ayushgoyal24/flask-mongo-app:latest
```

The image is hosted on Docker Hub to enable Kubernetes to pull it during deployment.

---

## Kubernetes Deployment

### Step 1: Start Minikube

```bash
# Start cluster with adequate resources
minikube start --cpus=4 --memory=4096

# Enable metrics-server for autoscaling
minikube addons enable metrics-server

# Verify cluster status
minikube status
```

### Step 2: Deploy All Resources

Apply all Kubernetes manifests:

```bash
# Deploy all resources at once
kubectl apply -f k8s/

# Verify deployment
kubectl get all
kubectl get pvc
```

Alternatively, deploy in order for better control:

```bash
kubectl apply -f k8s/mongodb-secret.yaml
kubectl apply -f k8s/mongodb-pv.yaml
kubectl apply -f k8s/mongodb-pvc.yaml
kubectl apply -f k8s/mongodb-statefulset.yaml
kubectl apply -f k8s/mongodb-service.yaml
kubectl apply -f k8s/flask-deployment.yaml
kubectl apply -f k8s/flask-service.yaml
kubectl apply -f k8s/flask-hpa.yaml
```

### Step 3: Access the Application

```bash
# Access the Flask service
minikube service flask-service

# This will automatically open the application in your browser
# Or get the URL to use manually
minikube service flask-service --url
```

---

## Testing the Application

### Basic Functionality

```bash
# Set service URL
SERVICE_URL=$(minikube service flask-service --url)

# Test welcome endpoint
curl $SERVICE_URL/

# Insert data
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"test","value":123}' $SERVICE_URL/data

# Retrieve data
curl $SERVICE_URL/data
```

### Data Persistence Test

```bash
# Insert test data
curl -X POST -H "Content-Type: application/json" \
  -d '{"test":"persistence"}' $SERVICE_URL/data

# Delete MongoDB pod to simulate failure
kubectl delete pod mongo-0

# Wait for pod restart
kubectl wait --for=condition=ready pod/mongo-0 --timeout=120s

# Verify data still exists
curl $SERVICE_URL/data
# Expected: All data including persistence test is returned
```

---

## DNS Resolution in Kubernetes

Kubernetes uses an internal DNS system (CoreDNS) for service discovery, eliminating the need for hardcoded IP addresses.

### How It Works

When a Service is created, Kubernetes automatically creates DNS records:

```
<service-name>.<namespace>.svc.cluster.local
```

For our setup:
- MongoDB: `mongo.default.svc.cluster.local` (short form: `mongo`)
- Flask: `flask-service.default.svc.cluster.local` (short form: `flask-service`)

### Inter-Pod Communication Flow

1. Flask pod needs to connect to MongoDB
2. Flask uses the service name `mongo` in connection URI
3. Pod's DNS resolver queries CoreDNS for `mongo`
4. CoreDNS returns the Service's internal IP address
5. Service load-balances the request to a healthy MongoDB pod
6. Connection is established

**Connection String Used:**
```python
mongodb://admin:password@mongo:27017/?authSource=admin
```

This approach ensures:
- No hardcoded IP addresses
- Automatic service discovery
- Load balancing across multiple pods
- Resilience to pod restarts (IP changes handled automatically)

### Verification

```bash
# Test DNS resolution from Flask pod
kubectl exec -it <flask-pod-name> -- nslookup mongo

# Expected output: Shows the service's internal IP
```

---

## Resource Management

Resource requests and limits are defined to ensure predictable performance and fair resource sharing.

### Configuration Values

```yaml
resources:
  requests:
    cpu: "200m"      # 0.2 CPU cores
    memory: "250Mi"  # 250 MiB RAM
  limits:
    cpu: "500m"      # 0.5 CPU cores
    memory: "500Mi"  # 500 MiB RAM
```

### Understanding Requests vs Limits

**Requests (Guaranteed Resources):**
- Minimum resources reserved for the pod
- Kubernetes scheduler uses this to find a suitable node
- Pod won't be scheduled if no node has available resources
- Ensures baseline performance under normal conditions

**Limits (Maximum Resources):**
- Maximum resources a pod can consume
- CPU: Pod is throttled if it exceeds the limit
- Memory: Pod is terminated (OOMKilled) if it exceeds the limit
- Prevents resource hogging and protects other workloads

### Why These Values?

**Requests (200m CPU, 250Mi Memory):**
- Sufficient for normal Flask/MongoDB operations
- Low enough to allow multiple pods on a single node
- Ensures scheduler can find available resources

**Limits (500m CPU, 500Mi Memory):**
- 2.5x multiplier allows burst capacity during traffic spikes
- Prevents runaway processes from consuming entire node resources
- Balances performance with resource efficiency

### Quality of Service (QoS)

With our configuration (requests < limits), pods receive **Burstable QoS**:
- Better than BestEffort (no guarantees)
- More flexible than Guaranteed (requests = limits)
- Optimal for web applications with variable load

### Monitoring Resources

```bash
# Check node resources
kubectl top nodes

# Check pod resource usage
kubectl top pods -l app=flask-app
```

---

## Horizontal Pod Autoscaler (HPA)

HPA automatically scales the Flask application based on CPU utilization.

### Configuration

- **Minimum replicas:** 2 (high availability)
- **Maximum replicas:** 5 (resource constraints)
- **CPU threshold:** 70% (scales when average CPU exceeds this)

### Autoscaling Test

**Test Method:**
Generated load using a temporary BusyBox pod running continuous wget requests from within the Kubernetes cluster:

```bash
kubectl run -it --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh

# Inside the pod shell:
while true; do wget -q -O- http://flask-service:5000/; done
```

**Monitoring:**
```bash
# Watch HPA in real-time
watch kubectl get hpa flask-hpa

# Monitor CPU usage
kubectl top pods -l app=flask-app
```

**Test Results:**

| Time | CPU Usage | Replicas | Event |
|------|-----------|----------|-------|
| 0:00 | 3% | 2 | Baseline |
| 1:30 | 78% | 2 | Load started |
| 3:00 | 85% | 3 | Scaled up |
| 4:30 | 82% | 4 | Further scaling |
| 8:00 | 15% | 4 | Load stopped |
| 13:00 | 4% | 2 | Scaled back down |

**Autoscaling in Action:**

![HPA Autoscaling Screenshot](hpa-pods.png)

*Screenshot shows HPA successfully scaled Flask application from 2 to 3 replicas when CPU utilization exceeded 70% threshold. The load-generator pod is visible, actively generating traffic to test autoscaling behavior.*

**Observations:**
- When CPU utilization crossed the 70% threshold, HPA increased Flask replicas from 2 to 3
- Scale-up latency: approximately 90 seconds from threshold breach
- After stopping the load, CPU usage dropped below threshold
- Scale-down occurred after 5-minute stabilization period (prevents flapping)
- No request failures during scaling events
- CPU load was distributed evenly across all replicas

**Issues Encountered:**
1. **Initial metrics delay (~60 seconds)** - This is expected behavior as metrics-server needs time to collect and aggregate CPU data
2. **Brief "NotReady" state during scale-up** - New pods showed NotReady for approximately 10 seconds while readiness probes were being checked, then automatically recovered

---

## Design Choices

### 1. Deployment for Flask vs StatefulSet

**Chosen:** Deployment

**Rationale:** Flask is stateless - each request is independent and doesn't require persistent identity. Deployments are ideal for stateless applications because they support easy scaling, rolling updates, and random pod naming.

**Alternative:** StatefulSet would provide stable identities but adds unnecessary complexity for stateless workloads.

---

### 2. StatefulSet for MongoDB vs Deployment

**Chosen:** StatefulSet

**Rationale:** MongoDB requires:
- **Stable network identity** (mongodb-0, mongodb-1) for clustering
- **Persistent storage** that follows the pod across restarts
- **Ordered deployment** for proper initialization

StatefulSet provides all these guarantees, making it the standard choice for databases.

**Alternative:** Deployment doesn't provide stable identities or persistent storage guarantees, making it unsuitable for stateful applications.

---

### 3. ClusterIP Service for MongoDB vs NodePort

**Chosen:** ClusterIP (Internal service only)

**Rationale:** 
- MongoDB should only be accessible within the cluster for security
- No external access needed - only Flask pods connect to it
- Reduces attack surface by keeping database internal
- Simplifies network configuration

**Alternative:** NodePort or LoadBalancer would expose MongoDB externally, creating a security vulnerability.

---

### 4. NodePort Service for Flask vs ClusterIP

**Chosen:** NodePort

**Rationale:**
- Enables external access for testing on Minikube
- Simpler than Ingress for local development
- No cloud load balancer required
- Works seamlessly with `minikube service` command

**Alternative:** ClusterIP would require port-forwarding for every access. LoadBalancer isn't supported by default on Minikube.

**Production:** Would use Ingress with TLS for better routing and security.

---

### 5. hostPath Storage vs Cloud Storage

**Chosen:** hostPath with PersistentVolume/PVC

**Rationale:**
- Works out-of-the-box on Minikube
- No external storage dependencies
- Sufficient for local development and testing

**Alternative:** Cloud storage (EBS, GCE Persistent Disk) would be used in production but requires cloud provider and adds complexity for local testing.

---

### 6. Resource Values (200m/250Mi - 500m/500Mi)

**Chosen:** 2.5x multiplier (limits = 2.5 × requests)

**Rationale:**
- Industry standard for web applications
- Provides burst capacity without waste
- Allows multiple pods on single node
- Prevents resource starvation

**Alternative:** 1x ratio (requests = limits) would be too restrictive and cause throttling. 5x+ would waste resources.

---

### 7. HPA Threshold at 70% vs 50% or 90%

**Chosen:** 70% CPU threshold

**Rationale:**
- Provides buffer before saturation
- Time for new pods to start before existing pods overwhelmed
- Industry standard for web services

**Alternative:** 50% would scale too aggressively (cost inefficient). 90% would scale too late (poor user experience).

---

### 8. Kubernetes Secrets vs ConfigMap

**Chosen:** Secrets for MongoDB credentials

**Rationale:**
- Designed for sensitive data
- Base64 encoded (basic obfuscation)
- Can be encrypted at rest with encryption providers
- Clear indication that data is sensitive

**Alternative:** ConfigMaps are for non-sensitive configuration. Using them for passwords is a security anti-pattern.

**Production:** Would use HashiCorp Vault or cloud secret managers for better security.

---

## Cookie Point: Virtual Environment Benefits

Virtual environments isolate project dependencies from system-wide Python packages.

**Key Benefits:**

1. **Dependency Isolation** - Each project has its own package versions, preventing conflicts between projects using different library versions

2. **Clean System** - System Python remains uncluttered, reducing risk of breaking system tools that depend on Python

3. **Reproducibility** - `requirements.txt` captures exact versions, making it easy to recreate the environment on any machine

4. **Version Management** - Different projects can use different Python versions (3.8, 3.9, 3.11) simultaneously

5. **Easy Cleanup** - Delete the virtual environment directory to remove all packages without affecting other projects

**Example Usage:**
```bash
# Create virtual environment
python3 -m venv venv

# Activate
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Work on project...

# Deactivate
deactivate
```

---

## Troubleshooting

### HPA Shows `<unknown>` Metrics

**Cause:** Metrics-server not running or metrics not yet available

**Solution:**
```bash
minikube addons enable metrics-server
# Wait 1-2 minutes for metrics to populate
kubectl get hpa flask-hpa
```

---

### MongoDB Authentication Failure

**Cause:** Incorrect credentials or connection string

**Solution:**
```bash
# Verify secret exists
kubectl get secret mongodb-secret

# Check Flask environment variables
kubectl exec -it <flask-pod> -- env | grep MONGODB

# Test MongoDB connection
kubectl exec -it mongo-0 -- mongosh -u admin -p password123
```

---

### PVC Not Binding

**Cause:** StorageClass or access mode mismatch

**Solution:**
```bash
# Check PV and PVC status
kubectl get pv
kubectl get pvc

# Ensure proper configuration
kubectl describe pvc mongodb-pvc

# Verify PV is available
kubectl get pv -o wide
```

---

### Service Not Accessible

**Cause:** Service not properly exposed or incorrect URL

**Solution:**
```bash
# Get correct service URL
minikube service flask-service --url

# Alternative: port-forward
kubectl port-forward service/flask-service 5000:5000
```

---

## Cleanup

```bash
# Delete all resources
kubectl delete -f k8s/

# Stop Minikube
minikube stop

# Delete cluster (optional)
minikube delete
```

---

## Conclusion

This deployment demonstrates production-ready patterns including high availability (multiple replicas), autoscaling (HPA), data persistence (StatefulSet with PVC), security (secrets management), and efficient resource utilization. The setup is fully functional on Minikube and can be adapted for production with minimal changes.

---
