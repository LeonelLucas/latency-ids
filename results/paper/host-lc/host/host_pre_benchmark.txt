runner_version=2026-07-20.1
profile=definitive
selected_cpu=7
data_dir=/home/miani/ladc_paper/ladc-data
run_root=/home/miani/ladc_paper/ladc-run-definitive-20260720T141840Z
strict_controls=1
max_load1=0.50
2026-07-20T11:29:45-03:00
Linux cartman 5.4.0-216-generic #236-Ubuntu SMP Fri Apr 11 19:53:21 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux

/proc/cmdline
BOOT_IMAGE=/boot/vmlinuz-5.4.0-216-generic root=UUID=c88e8df0-ed02-465c-a78a-179c3faaf0ca ro

lscpu
Architecture:                       x86_64
CPU op-mode(s):                     32-bit, 64-bit
Byte Order:                         Little Endian
Address sizes:                      36 bits physical, 48 bits virtual
CPU(s):                             8
On-line CPU(s) list:                0-7
Thread(s) per core:                 2
Core(s) per socket:                 4
Socket(s):                          1
NUMA node(s):                       1
Vendor ID:                          GenuineIntel
CPU family:                         6
Model:                              58
Model name:                         Intel(R) Core(TM) i7-3770 CPU @ 3.40GHz
Stepping:                           9
CPU MHz:                            2234.389
CPU max MHz:                        3900.0000
CPU min MHz:                        1600.0000
BogoMIPS:                           6784.34
Virtualization:                     VT-x
L1d cache:                          128 KiB
L1i cache:                          128 KiB
L2 cache:                           1 MiB
L3 cache:                           8 MiB
NUMA node0 CPU(s):                  0-7
Vulnerability Gather data sampling: Not affected
Vulnerability Itlb multihit:        KVM: Mitigation: Split huge pages
Vulnerability L1tf:                 Mitigation; PTE Inversion; VMX conditional cache flushes, SMT vulnerable
Vulnerability Mds:                  Mitigation; Clear CPU buffers; SMT vulnerable
Vulnerability Meltdown:             Mitigation; PTI
Vulnerability Mmio stale data:      Unknown: No mitigations
Vulnerability Retbleed:             Not affected
Vulnerability Spec store bypass:    Mitigation; Speculative Store Bypass disabled via prctl and seccomp
Vulnerability Spectre v1:           Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2:           Mitigation; Retpolines; IBPB conditional; IBRS_FW; STIBP conditional; RSB filling; PBRSB-eIBRS Not affected; BHI Not affected
Vulnerability Srbds:                Vulnerable: No microcode
Vulnerability Tsx async abort:      Not affected
Flags:                              fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx rdtscp lm constant_tsc arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm cpuid_fault epb pti ssbd ibrs ibpb stibp tpr_shadow vnmi flexpriority ept vpid fsgsbase smep erms xsaveopt dtherm ida arat pln pts md_clear flush_l1d

nproc
8
8

/proc/loadavg
0.43 0.77 0.52 1/815 105470

free
              total        used        free      shared  buff/cache   available
Mem:           15Gi       591Mi       2.2Gi        23Mi        12Gi        14Gi
Swap:         4.0Gi       364Mi       3.6Gi

df
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda2       457G  136G  299G  32% /
/dev/sda2       457G  136G  299G  32% /
/dev/sda2       457G  136G  299G  32% /

clocksource
tsc

selected_cpu_sysfs
/sys/devices/system/cpu/cpu7/cpufreq/scaling_governor=performance
/sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq=3430582
/sys/devices/system/cpu/cpu7/cpufreq/cpuinfo_max_freq=3900000
/sys/devices/system/cpu/intel_pstate/no_turbo=0

uptime
 11:29:45 up 36 days,  4:42,  1 user,  load average: 0.43, 0.77, 0.52

top_cpu_processes
    PID PSR %CPU %MEM COMMAND
 104673   1  1.4  0.5 dockerd
   1359   7  0.4  0.3 mysqld
    915   2  0.2  0.3 mongod
      1   2  0.0  0.0 systemd
      2   5  0.0  0.0 kthreadd
      3   0  0.0  0.0 rcu_gp
      4   0  0.0  0.0 rcu_par_gp
      6   0  0.0  0.0 kworker/0:0H-kblockd
      8   0  0.0  0.0 mm_percpu_wq
      9   0  0.0  0.0 ksoftirqd/0
     10   7  0.0  0.0 rcu_sched
     11   0  0.0  0.0 migration/0
     12   0  0.0  0.0 idle_inject/0
     14   0  0.0  0.0 cpuhp/0
     15   1  0.0  0.0 cpuhp/1
     16   1  0.0  0.0 idle_inject/1
     17   1  0.0  0.0 migration/1
     18   1  0.0  0.0 ksoftirqd/1
     20   1  0.0  0.0 kworker/1:0H-kblockd
     21   2  0.0  0.0 cpuhp/2
     22   2  0.0  0.0 idle_inject/2
     23   2  0.0  0.0 migration/2
     24   2  0.0  0.0 ksoftirqd/2
     26   2  0.0  0.0 kworker/2:0H-kblockd

docker_version
Client:
 Version:           26.1.3
 API version:       1.45
 Go version:        go1.22.2
 Git commit:        26.1.3-0ubuntu1~20.04.1
 Built:             Mon Oct 14 22:06:01 2024
 OS/Arch:           linux/amd64
 Context:           default

Server:
 Engine:
  Version:          26.1.3
  API version:      1.45 (minimum version 1.24)
  Go version:       go1.22.2
  Git commit:       26.1.3-0ubuntu1~20.04.1
  Built:            Mon Oct 14 22:06:01 2024
  OS/Arch:          linux/amd64
  Experimental:     false
 containerd:
  Version:          1.7.24
  GitCommit:        
 runc:
  Version:          1.1.12-0ubuntu2~20.04.1
  GitCommit:        
 docker-init:
  Version:          0.19.0
  GitCommit:        

docker_info
Client:
 Version:    26.1.3
 Context:    default
 Debug Mode: false

Server:
 Containers: 0
  Running: 0
  Paused: 0
  Stopped: 0
 Images: 10
 Server Version: 26.1.3
 Storage Driver: overlay2
  Backing Filesystem: extfs
  Supports d_type: true
  Using metacopy: false
  Native Overlay Diff: true
  userxattr: false
 Logging Driver: json-file
 Cgroup Driver: cgroupfs
 Cgroup Version: 1
 Plugins:
  Volume: local
  Network: bridge host ipvlan macvlan null overlay
  Log: awslogs fluentd gcplogs gelf journald json-file local splunk syslog
 Swarm: inactive
 Runtimes: io.containerd.runc.v2 runc
 Default Runtime: runc
 Init Binary: docker-init
 containerd version: 
 runc version: 
 init version: 
 Security Options:
  apparmor
  seccomp
   Profile: builtin
 Kernel Version: 5.4.0-216-generic
 Operating System: Ubuntu 20.04.6 LTS
 OSType: linux
 Architecture: x86_64
 CPUs: 8
 Total Memory: 15.51GiB
 Name: cartman
 ID: a052d618-69a7-420a-b78d-a7704a225d67
 Docker Root Dir: /var/lib/docker
 Debug Mode: false
 Experimental: false
 Insecure Registries:
  127.0.0.0/8
 Live Restore Enabled: false

WARNING: No swap limit support
