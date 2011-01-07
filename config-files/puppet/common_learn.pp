class common_1 {
    file { "/root/testf1.file":
        ## Section will stage file from /etc/puppet/files
        ## and assign permissions as described
        source => "puppet://puppet/files/testf1.file",
        owner => "root",
        group => "bitnami",
        mode => 600,
        ensure => present;
        "/root/testf3.file":
        content => "This is straight from common_learn.pp.\n"
#        require => File ["/root/prereq"],
    }
}

class common_2 {
    file { "/root/testf2.file":
        ## Section will stage file from /etc/puppet/files
        ## and assign permissions as described
        source => "puppet://puppet/files/testf2.file",
        owner => "root",
        group => "bitnami",
        mode => 600,
        ensure => present;
        ## Section will remove file no longer needed
           "/root/not_needed":
        ensure => absent;
        ## End section
    }
}

class common_3 {
    ## First we create a directory if one does not exist
    file { "/root/labdir":
        ensure => directory,
        owner => "bitnami",
        group => "bitnami",
        mode => 755;
    }

    file { "/root/labdir/testf4.file":
        ## Section will stage file from /etc/puppet/files
        ## and assign permissions as described
        source => "puppet://puppet/files/testf4.file",
        owner => "root",
        group => "bitnami",
        mode => 600,
        ensure => present;

        # "/root/testf3.file":
        # content => "This is straight from common_learn.pp.\n"
        # require => File ["/root/prereq"],
    }
}

class common_4 {
    file { "/root/labdir/testf5.file":
        source => "puppet://puppet/files/testf5.file",
        owner => "bitnami",
        group => "bitnami",
        mode => 600,
        ## Below, we create an alias just to make it easier
        ## to reference the file later in the class
        alias => file_testf5,
        ## We make sure that the file exists, and if not
        ## we create the file
        ensure => present;
    }
    service { ntp:
        ## Below, we make sure that the 'ntp' service
        ## is running (or, is restarted) upon addition
        ## of file defined earlier in the class
        ensure => running,
        subscribe => File[file_testf5];
    }
}

class common_pkg_1 {
    package { "wget":
        ## We make sure that the file exists, and if not
        ## we create the file
        ensure => installed,
        alias => wg;
    }
    service { "bitnami":
        ## Below, we make sure that the 'bitnami' service
        ## is running (or, is restarted) upon addition
        ## of package 'wget' defined earlier in the class
        ## While not practical, useful for learning
        ensure => running,
        subscribe => Package[wg];
    }
}

class cron_service {
    package { "cron":
        ensure => installed,
        alias => cron_pkg;
    }

    service { "cron":
        require => Package["cron_pkg"],
        ensure => running,
        alias => cron_svc;
    }
}

class common_pkg_2 {
    file { "/root/cron_is_ok":
        owner => "bitnami",
        group => "bitnami",
        mode => 600,
        ensure => present,
        # require => Package[cron_pkg],
        # require => Service[cron_svc]; 
        require => Class[cron_service];
    }
}
## End of file

