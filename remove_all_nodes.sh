for vm in master worker1 worker2; do
    virsh destroy $vm || true
    virsh undefine $vm --remove-all-storage || true
done

rm -f master-seed.iso worker1-seed.iso worker2-seed.iso
rm -f k8s-master.qcow2 k8s-worker1.qcow2 k8s-worker2.qcow2
