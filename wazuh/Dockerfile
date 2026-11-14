FROM wazuh/wazuh-manager:4.14.9

# 1. ossec.conf: build vao image, khong mount truc tiep
#    Sua: wazuh/config/wazuh_cluster/wazuh_manager.conf -> up -d --build
COPY config/wazuh_cluster/wazuh_manager.conf /wazuh-config-mount/etc/ossec.conf

# 2. filebeat.yml: bat ca alerts.enabled va archives.enabled = true
RUN f=/etc/filebeat/filebeat.yml; \
    if [ -f "$f" ]; then \
      sed -i '/alerts:/{n;s/enabled: false/enabled: true/}' "$f" && \
      sed -i '/archives:/{n;s/enabled: false/enabled: true/}' "$f" && \
      echo "=== filebeat.yml sau khi sua ===" && \
      grep -A2 'alerts:\|archives:' "$f"; \
    else \
      echo "WARN: $f not found"; \
    fi
