FROM wazuh/wazuh-manager:4.14.9

# ossec.conf: đi qua staging /wazuh-config-mount (cơ chế của image)
COPY config/wazuh_cluster/wazuh_manager.conf /wazuh-config-mount/etc/ossec.conf

# filebeat.yml nằm trong PERMANENT_DATA_EXCP -> image KHÔI PHỤC nó từ bản
# /var/ossec/data_tmp/exclusion/... mỗi lần boot, đè lên path live.
# Vì vậy phải ghi file của ta vào ĐÚNG nguồn restore đó, không phải /etc/filebeat.
COPY --chown=root:root config/filebeat.yml /var/ossec/data_tmp/exclusion/etc/filebeat/filebeat.yml
