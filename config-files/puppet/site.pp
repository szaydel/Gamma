import "nodes"
import "common_learn"

# class commonone {
#    file { "/root/file_t1":
#        owner => "root",
#        group => "bitnami",
#        mode => 600,
#    }
# }

# file { "/etc/passwd":
#    owner => "root",
#    group => "bin",
#    mode => 644,
# }

## Moved node to nodes.pp file
## no need to add nodes here
# node 'puppet-cli1.usa.dce.usps.gov' {
#    include commonone
# }
