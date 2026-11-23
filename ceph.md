# ceph

## chrony
```
sudo apt install -y podman lvm2 chrony cephadm ceph-common 
sudo systemctl enable --now chrony
sudo timedatectl set-timezone Asia/Jakarta
```

## bootstrap ceph
```
sudo cephadm bootstrap \
  --mon-ip 172.16.2.64 \
  --cluster-network 172.16.3.0/24 \
  --ssh-user rizwan \
  --initial-dashboard-user admin \
  --initial-dashboard-password 'changeme'
```

## copy ceph key
```
ssh-copy-id -f -i /etc/ceph/ceph.pub rizwan@172.16.2.65
ssh-copy-id -f -i /etc/ceph/ceph.pub rizwan@172.16.2.66
```

## add ceph host
```
sudo cephadm shell -- ceph orch host add kp-openstack-compute-02 172.16.2.65 --labels _admin
sudo cephadm shell -- ceph orch host add kp-openstack-compute-03 172.16.2.66 --labels _admin
sudo cephadm shell -- ceph orch host ls
```

## add mon + mgr
```
sudo cephadm shell -- ceph orch apply mon --placement="3 kp-openstack-compute-01 kp-openstack-compute-02 kp-openstack-compute-03"
sudo cephadm shell -- ceph orch apply mgr --placement="3 kp-openstack-compute-01 kp-openstack-compute-02 kp-openstack-compute-03"
```

## apply osd
```
sudo cephadm shell -- ceph orch apply osd --all-available-devices
```

## verification
```
sudo cephadm shell -- ceph -s          # 9 osd up/in, pg active+clean
sudo cephadm shell -- ceph osd tree
```

## create ceph pools
```
sudo cephadm shell -- bash -c 'for p in images volumes; do ceph osd pool create $p; rbd pool init $p; done'
```

## create ceph pools user
```
sudo cephadm shell -- ceph auth get-or-create client.glance \
  mon 'profile rbd' \
  osd 'profile rbd pool=images' \
  mgr 'profile rbd pool=images'

sudo cephadm shell -- ceph auth get-or-create client.cinder \
  mon 'profile rbd' \
  osd 'profile rbd pool=volumes, profile rbd-read-only pool=images' \
  mgr 'profile rbd pool=volumes'
```

## secret for kolla ansible
```
sudo cephadm shell -- ceph config generate-minimal-conf
sudo cephadm shell -- ceph auth get client.glance
sudo cephadm shell -- ceph auth get client.cinder
```

## put these file in deployer
```
/etc/kolla/config/glance/ceph.conf
/etc/kolla/config/glance/ceph.client.glance.keyring
/etc/kolla/config/cinder/cinder-volume/ceph.conf
/etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring
/etc/kolla/config/nova/ceph.conf
/etc/kolla/config/nova/ceph.client.cinder.keyring
```

# NOTES
## docker socket failed (compute)
- if docker socket failed, run this command
```
sudo systemctl unmask docker.service docker.socket
sudo systemctl stop docker.socket docker.service
sudo systemctl daemon-reload
sudo systemctl reset-failed docker.service docker.socket
sudo systemctl start docker.socket
sudo systemctl start docker.service
sudo systemctl status containerd docker --no-pager | grep -E 'Active|●'
sudo docker info | head -5
```

## create volume type
```
openstack volume type create synology --property volume_backend_name=synology
openstack volume type create ceph --property volume_backend_name=ceph
```