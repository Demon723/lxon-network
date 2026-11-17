# Production Monitoring Configuration

**Date:** 2025-01-15
**Environment:** Mainnet (Chain ID 724)
**Status:** ✅ Monitoring Configuration Ready

---

## 📊 Monitoring Overview

Comprehensive monitoring configuration for the LXON multi-layer blockchain ecosystem production deployment.

---

## 🔍 Component Monitoring

### 1. L1 Mainnet Monitoring

**Health Endpoints:**
- `http://13.51.158.120:8546` - Main RPC endpoint
- `http://13.51.158.120:8546/health` - Health check endpoint

**Metrics to Monitor:**
- Block height and block time
- Transaction throughput
- Network difficulty
- Peer connection count
- Gas price
- Chain state root

**Alert Thresholds:**
- Block time > 15s: ⚠️ Warning
- Block time > 30s: 🚨 Critical
- Transaction throughput < 1 tx/s: ⚠️ Warning
- Peer connections < 3: ⚠️ Warning
- Peer connections < 1: 🚨 Critical

### 2. L2 Sequencer Monitoring

**Health Endpoints:**
- `http://13.51.158.120:8547/health` - Health check
- `http://13.51.158.120:8547/metrics` - Prometheus metrics

**Metrics to Monitor:**
- Batch submission rate
- Mempool size
- State root anchoring status
- L1 connectivity
- Sequencer uptime
- Transaction processing latency

**Alert Thresholds:**
- Batch submission rate < 1 batch/min: ⚠️ Warning
- Mempool size > 100000: ⚠️ Warning
- L1 connectivity lost: 🚨 Critical
- Transaction latency > 5s: ⚠️ Warning
- Transaction latency > 10s: 🚨 Critical

### 3. L3 Mint Monitoring

**Health Endpoints:**
- `http://13.51.158.120:8548/health` - Health check
- `http://13.51.158.120:8548/metrics` - Prometheus metrics

**Metrics to Monitor:**
- Token minting rate
- Chip registration rate
- Redemption processing rate
- Contract interaction count
- Error rates
- Gas usage efficiency

**Alert Thresholds:**
- Error rate > 5%: ⚠️ Warning
- Error rate > 10%: 🚨 Critical
- Contract interaction count = 0 for 1h: ⚠️ Warning
- Gas usage efficiency < 50%: ⚠️ Warning

### 4. Satellite Relay Monitoring

**Health Endpoints:**
- `http://13.51.158.120:8549/health` - Health check
- `http://13.51.158.120:8549/metrics` - Prometheus metrics

**Metrics to Monitor:**
- DTN bundle processing rate
- Satellite communication success rate
- Ground station connectivity
- Data transmission latency
- Bundle queue size
- Orbit prediction accuracy

**Alert Thresholds:**
- Communication success rate < 90%: ⚠️ Warning
- Communication success rate < 80%: 🚨 Critical
- Ground station connectivity lost: 🚨 Critical
- Bundle queue size > 1000: ⚠️ Warning
- Data transmission latency > 30s: ⚠️ Warning

### 5. Space Node Monitoring

**Health Endpoints:**
- `http://13.51.158.120:8550/health` - Health check
- `http://13.51.158.120:8550/metrics` - Prometheus metrics

**Metrics to Monitor:**
- Satellite pass tracking
- Ground station connectivity
- L2 integration status
- Data processing rate
- Constellation health
- Position accuracy

**Alert Thresholds:**
- Satellite pass tracking failure: 🚨 Critical
- Ground station connectivity lost: 🚨 Critical
- L2 integration failure: 🚨 Critical
- Data processing rate < 1 msg/min: ⚠️ Warning

### 6. PQ Security Monitoring

**Health Endpoints:**
- `http://13.51.158.120:8551/health` - Health check
- `http://13.51.158.120:8551/metrics` - Prometheus metrics

**Metrics to Monitor:**
- PQ signature verification rate
- Hybrid signature verification rate
- Key encapsulation operations
- PQ library health
- Security event count
- Compliance status

**Alert Thresholds:**
- PQ signature verification failure: 🚨 Critical
- Security event count > 0: 🚨 Critical
- Compliance status non-compliant: 🚨 Critical
- PQ library health check failure: 🚨 Critical

---

## 📈 Prometheus Metrics Configuration

### L1 Mainnet Metrics

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'lxon-l1'
    static_configs:
      - targets: ['13.51.158.120:8546']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

**Prometheus Queries:**
```promql
# Block production rate
rate(lxon_block_height[5m])

# Transaction throughput
rate(lxon_transaction_count[5m])

# Peer connections
lxon_peer_connections

# Gas price
lxon_gas_price_gwei
```

### L2 Sequencer Metrics

```yaml
  - job_name: 'lxon-l2-sequencer'
    static_configs:
      - targets: ['13.51.158.120:8547']
    metrics_path: '/metrics'
    scrape_interval: 10s
```

**Prometheus Queries:**
```promql
# Batch submission rate
rate(lxon_batch_submissions[5m])

# Mempool size
lxon_mempool_size

# L1 connectivity
lxon_l1_connectivity_status

# Transaction latency
histogram_quantile(0.95, lxon_transaction_latency_seconds)
```

### L3 Mint Metrics

```yaml
  - job_name: 'lxon-l3-mint'
    static_configs:
      - targets: ['13.51.158.120:8548']
    metrics_path: '/metrics'
    scrape_interval: 10s
```

**Prometheus Queries:**
```promql
# Token minting rate
rate(lxon_token_minting[5m])

# Error rate
rate(lxon_contract_errors[5m])

# Gas usage efficiency
lxon_gas_efficiency_percentage
```

---

## 🚨 Alerting Configuration

### Alert Rules

```yaml
# alerting_rules.yml
groups:
  - name: lxon_mainnet
    rules:
      - alert: L1BlockTimeHigh
        expr: lxon_block_time_seconds > 30
        for: 5m
        labels:
          severity: critical
          component: l1-mainnet
        annotations:
          summary: "L1 block time too high"
          description: "L1 block time is {{ $value }}s (threshold: 30s)"

      - alert: L1PeerConnectionsLow
        expr: lxon_peer_connections < 1
        for: 2m
        labels:
          severity: critical
          component: l1-mainnet
        annotations:
          summary: "L1 peer connections too low"
          description: "L1 has {{ $value }} peer connections (threshold: 1)"

  - name: lxon_l2_sequencer
    rules:
      - alert: L2MempoolHigh
        expr: lxon_mempool_size > 100000
        for: 5m
        labels:
          severity: warning
          component: l2-sequencer
        annotations:
          summary: "L2 mempool size too high"
          description: "L2 mempool size is {{ $value }} (threshold: 100000)"

      - alert: L2L1ConnectivityLost
        expr: lxon_l1_connectivity_status == 0
        for: 1m
        labels:
          severity: critical
          component: l2-sequencer
        annotations:
          summary: "L2 lost L1 connectivity"
          description: "L2 sequencer cannot connect to L1 mainnet"

  - name: lxon_l3_mint
    rules:
      - alert: L3ErrorRateHigh
        expr: rate(lxon_contract_errors[5m]) > 0.1
        for: 5m
        labels:
          severity: critical
          component: l3-mint
        annotations:
          summary: "L3 error rate too high"
          description: "L3 error rate is {{ $value }} (threshold: 10%)"

  - name: lxon_satellite
    rules:
      - alert: SatelliteCommunicationFailure
        expr: lxon_satellite_communication_success_rate < 0.8
        for: 5m
        labels:
          severity: critical
          component: satellite-relay
        annotations:
          summary: "Satellite communication failure"
          description: "Satellite communication success rate is {{ $value }} (threshold: 80%)"

      - alert: GroundStationConnectivityLost
        expr: lxon_ground_station_connectivity == 0
        for: 1m
        labels:
          severity: critical
          component: satellite-relay
        annotations:
          summary: "Ground station connectivity lost"
          description: "Cannot connect to ground station"

  - name: lxon_pq_security
    rules:
      - alert: PQSecurityEvent
        expr: lxon_security_event_count > 0
        for: 0s
        labels:
          severity: critical
          component: pq-security
        annotations:
          summary: "PQ security event detected"
          description: "Security event count is {{ $value }}"
```

---

## 📊 Grafana Dashboard Configuration

### Main Dashboard

```json
{
  "dashboard": {
    "title": "LXON Multi-Layer Mainnet",
    "panels": [
      {
        "title": "L1 Block Height",
        "targets": [
          {
            "expr": "lxon_block_height"
          }
        ]
      },
      {
        "title": "L2 Batch Submission Rate",
        "targets": [
          {
            "expr": "rate(lxon_batch_submissions[5m])"
          }
        ]
      },
      {
        "title": "L3 Token Minting Rate",
        "targets": [
          {
            "expr": "rate(lxon_token_minting[5m])"
          }
        ]
      },
      {
        "title": "Satellite Communication Success Rate",
        "targets": [
          {
            "expr": "lxon_satellite_communication_success_rate"
          }
        ]
      },
      {
        "title": "PQ Security Status",
        "targets": [
          {
            "expr": "lxon_security_event_count"
          }
        ]
      }
    ]
  }
}
```

---

## 🔧 Monitoring Stack Setup

### 1. Prometheus Setup

```bash
# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
tar xvfz prometheus-2.45.0.linux-amd64.tar.gz
cd prometheus-2.45.0.linux-amd64

# Create configuration
cat > prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'lxon-l1'
    static_configs:
      - targets: ['13.51.158.120:8546']
    metrics_path: '/metrics'
    scrape_interval: 15s

  - job_name: 'lxon-l2-sequencer'
    static_configs:
      - targets: ['13.51.158.120:8547']
    metrics_path: '/metrics'
    scrape_interval: 10s

  - job_name: 'lxon-l3-mint'
    static_configs:
      - targets: ['13.51.158.120:8548']
    metrics_path: '/metrics'
    scrape_interval: 10s

  - job_name: 'lxon-satellite-relay'
    static_configs:
      - targets: ['13.51.158.120:8549']
    metrics_path: '/metrics'
    scrape_interval: 10s

  - job_name: 'lxon-space-node'
    static_configs:
      - targets: ['13.51.158.120:8550']
    metrics_path: '/metrics'
    scrape_interval: 10s

  - job_name: 'lxon-pq-security'
    static_configs:
      - targets: ['13.51.158.120:8551']
    metrics_path: '/metrics'
    scrape_interval: 10s
EOF

# Start Prometheus
./prometheus --config.file=prometheus.yml
```

### 2. Grafana Setup

```bash
# Install Grafana
wget https://dl.grafana.com/oss/release/grafana-10.2.0.linux-amd64.tar.gz
tar -zxvf grafana-10.2.0.linux-amd64.tar.gz
cd grafana-10.2.0

# Start Grafana
./bin/grafana server
```

### 3. Alertmanager Setup

```bash
# Install Alertmanager
wget https://github.com/prometheus/alertmanager/releases/download/v0.26.0/alertmanager-0.26.0.linux-amd64.tar.gz
tar xvfz alertmanager-0.26.0.linux-amd64.tar.gz
cd alertmanager-0.26.0.linux-amd64

# Create configuration
cat > alertmanager.yml <<EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'

  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
    - match:
        severity: warning
      receiver: 'warning-alerts'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/webhook'

  - name: 'critical-alerts'
    webhook_configs:
      - url: 'http://localhost:5001/critical'
    email_configs:
      - to: 'oncall@lxon.io'
        from: 'alerts@lxon.io'

  - name: 'warning-alerts'
    webhook_configs:
      - url: 'http://localhost:5001/warning'
    email_configs:
      - to: 'devops@lxon.io'
        from: 'alerts@lxon.io'
EOF

# Start Alertmanager
./alertmanager --config.file=alertmanager.yml
```

---

## 📱 Notification Channels

### Email Notifications

**Critical Alerts:**
- Recipients: oncall@lxon.io, security@lxon.io
- Priority: Immediate
- Format: [CRITICAL] LXON Alert - Component Name

**Warning Alerts:**
- Recipients: devops@lxon.io
- Priority: Normal
- Format: [WARNING] LXON Alert - Component Name

### Slack Integration

```json
{
  "webhook_url": "https://hooks.slack.com/services/YOUR/WEBHOOK/URL",
  "channel": "#lxon-alerts",
  "username": "LXON Monitor",
  "icon_emoji": ":warning:"
}
```

### PagerDuty Integration

```yaml
# Alertmanager configuration
pagerduty_configs:
  - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
    description: '{{ .GroupLabels.alertname }}'
    severity: '{{ .CommonLabels.severity }}'
```

---

## 🔍 Log Aggregation

### Loki Setup

```bash
# Install Loki
wget https://github.com/grafana/loki/releases/download/v2.9.0/loki-linux-amd64.zip
unzip loki-linux-amd64.zip

# Create configuration
cat > loki-config.yml <<EOF
server:
  http_listen_port: 3100

positions:
  filename: /tmp/loki/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: lxon-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: lxon
          __path__: /var/log/lxon/*.log
EOF

# Start Loki
./loki-linux-amd64 -config.file=loki-config.yml
```

### Promtail Setup

```bash
# Install Promtail
wget https://github.com/grafana/loki/releases/download/v2.9.0/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip

# Create configuration
cat > promtail-config.yml <<EOF
server:
  http_listen_port: 9080

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: lxon-system
    static_configs:
      - targets:
          - localhost
        labels:
          job: lxon-system
          __path__: /var/log/syslog

  - job_name: lxon-application
    static_configs:
      - targets:
          - localhost
        labels:
          job: lxon-application
          __path__: /var/log/lxon/*.log
EOF

# Start Promtail
./promtail-linux-amd64 -config.file=promtail-config.yml
```

---

## 🎯 Monitoring Checklist

### Pre-Deployment
- [ ] Install Prometheus server
- [ ] Install Grafana dashboard
- [ ] Install Alertmanager
- [ ] Configure alerting rules
- [ ] Set up notification channels
- [ ] Install Loki for log aggregation
- [ ] Install Promtail for log collection
- [ ] Configure Prometheus targets
- [ ] Test alerting pipeline
- [ ] Create Grafana dashboards

### During Deployment
- [ ] Verify Prometheus is scraping all targets
- [ ] Check Grafana dashboards are displaying data
- [ ] Test alert notifications
- [ ] Verify log aggregation is working
- [ ] Monitor deployment metrics
- [ ] Check component health endpoints
- [ ] Verify alert thresholds are appropriate

### Post-Deployment
- [ ] Adjust alert thresholds based on production behavior
- [ ] Fine-tune Grafana dashboards
- [ ] Optimize log retention policies
- [ ] Set up long-term metric storage
- [ ] Configure backup and recovery for monitoring stack
- [ ] Document monitoring procedures
- [ ] Train operations team on monitoring tools

---

## 📊 Monitoring Best Practices

### 1. Alert Fatigue Prevention
- Use appropriate alert thresholds
- Implement alert grouping and deduplication
- Set up alert routing based on severity
- Use different notification channels for different severity levels

### 2. Metric Retention
- Store high-resolution metrics for 7 days
- Store medium-resolution metrics for 30 days
- Store low-resolution metrics for 1 year
- Implement data compression for long-term storage

### 3. Dashboard Organization
- Create separate dashboards for each component
- Create overview dashboard for all components
- Use consistent color schemes
- Include context and documentation in dashboards

### 4. Log Management
- Implement log rotation
- Set appropriate log levels for production
- Include correlation IDs in logs
- Implement structured logging

---

## 🚨 Incident Response

### Critical Incident Response Procedure

1. **Detection**
   - Alert triggers for critical threshold
   - On-call team receives notification
   - Automated escalation if no response

2. **Assessment**
   - Check component health endpoints
   - Review metrics and logs
   - Determine impact scope

3. **Mitigation**
   - Implement immediate fixes
   - Scale affected components if needed
   - Notify stakeholders

4. **Resolution**
   - Verify fix resolves the issue
   - Monitor for recurrence
   - Document incident

5. **Post-Incident**
   - Conduct root cause analysis
   - Implement preventive measures
   - Update monitoring thresholds

---

**Configuration Status:** ✅ Ready for Deployment
**Next Steps:** Install monitoring stack and configure alerts
**Contact:** devops@lxon.io for monitoring infrastructure setup