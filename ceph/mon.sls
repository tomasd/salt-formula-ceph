{%- from "ceph/map.jinja" import common, mon with context %}

include:
- ceph.common
- ceph.conf

mon_packages:
  pkg.installed:
  - names: {{ mon.pkgs }}
  - require_in:
    - file: /etc/ceph/ceph.conf


cluster_{{ grains.host }}_secret_key:
  cmd.run:
  - name: "ceph-authtool --create-keyring /etc/ceph/ceph.mon.{{ grains.host }}.keyring --gen-key -n mon. --cap mon 'allow *'"
  - unless: "test -f /etc/ceph/ceph.mon.{{ grains.host }}.keyring"
  - require:
    - pkg: mon_packages

add_admin_keyring_to_mon_keyring:
  cmd.run:
  - name: "ceph-authtool /etc/ceph/ceph.mon.{{ grains.host }}.keyring --import-keyring /etc/ceph/ceph.client.admin.keyring"
  - unless: "test -f /var/lib/ceph/mon/ceph-{{ grains.host }}/done"
  - require:
    - pkg: mon_packages

generate_monmap:
  cmd.run:
  - name: "monmaptool --create {%- for member in common.members %} --add {{ member.name }} {{ member.host }} {%- endfor %} --fsid {{ common.fsid }} /tmp/monmap"
  - unless: "test -f /tmp/monmap"
  - require:
    - pkg: mon_packages

#/var/lib/ceph/mon/ceph-{{ grains.host }}:
#  file.directory:
#    - user: ceph
#    - group: ceph
#    - mode: 655
#    - makedirs: True

/etc/ceph/ceph.mon.{{ grains.host }}.keyring:
  file.managed:
  - user: ceph
  - group: ceph
  - replace: false
  - require:
    - pkg: mon_packages

populate_monmap:
  cmd.run:
  - name: "sudo -u ceph ceph-mon --mkfs -i {{ grains.host }} --monmap /tmp/monmap"
  - unless: "test -f /var/lib/ceph/mon/ceph-{{ grains.host }}/kv_backend"
  - require:
    - pkg: mon_packages

{% for keyring_name, keyring in mon.get('keyring', {}).iteritems() %}

{%- if keyring_name == 'mon' and keyring.key is undefined %}

cluster_secret_key:
  cmd.run:
  - name: "ceph-authtool --create-keyring /var/lib/ceph/mon/ceph-{{ grains.host }}/keyring --gen-key -n mon. {%- for cap_name, cap in  keyring.caps.iteritems() %} --cap {{ cap_name }} '{{ cap }}' {%- endfor %}"
  - unless: "test -f /var/lib/ceph/mon/ceph-{{ grains.host }}/done"
  - require:
    - pkg: mon_packages

cluster_secret_key_flag:
  file.managed:
  - name: /var/lib/ceph/mon/ceph-{{ grains.host }}/done
  - user: ceph
  - group: ceph
  - content: { }
  - require:
    - pkg: mon_packages

{%- endif %}

{% endfor %}

/var/lib/ceph/mon/ceph-{{ grains.host }}/keyring:
  file.managed:
  - source: salt://ceph/files/mon_keyring
  - template: jinja
  - unless: "test -f /var/lib/ceph/mon/ceph-{{ grains.host }}/done"
  - require:
    - pkg: mon_packages

/var/lib/ceph/mon/ceph-{{ grains.host }}/done:
  file.managed:
  - user: ceph
  - group: ceph
  - content: { }
  - require:
    - pkg: mon_packages

mon_services:
  service.running:
  - enable: true
  - names: [ceph-mon@{{ grains.host }}]
  - watch:
    - file: /etc/ceph/ceph.conf
  - require:
    - pkg: mon_packages
  {%- if grains.get('noservices') %}
  - onlyif: /bin/false
  {%- endif %}
