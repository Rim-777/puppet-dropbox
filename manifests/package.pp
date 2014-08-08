class dropbox::package {
  Exec {
    path   => '/bin:/sbin:/usr/bin:/usr/sbin',
  }

  $download_arch = $::architecture ? {
    'i386'   => 'x86',
    'x86_64' => 'x86_64',
    'amd64'  => 'x86_64',
  }

  user { $dropbox::config::dx_uid:
    ensure     => present,
    gid        => $dropbox::config::dx_gid,
    managehome => true,
    system     => true,
    home       => $dropbox::config::dx_home,
    comment    => 'Dropbox Service Account',
  }
  group { $dropbox::config::dx_gid:
    ensure => present,
    system => true
  }

  file { "${dropbox::config::dx_home}/tmp":
    ensure => directory,
  } ->
  exec { 'download-dropbox-cli':
    command => "wget -O ${dropbox::config::dx_home}/tmp/dropbox.py \"https://www.dropbox.com/download?dl=packages/dropbox.py\"",
    unless  => "test -f ${dropbox::config::dx_home}/tmp/dropbox.py",
    require => User[$dropbox::config::dx_uid],
  } ->
  file { '/usr/local/bin/dropbox':
    source  => "${dropbox::config::dx_home}/tmp/dropbox.py",
    mode    => 755,
  }

  if ($dropbox::config::user != undef and $dropbox::config::password != undef) {
    if $::lsbdistcodename == 'squeeze' {
      apt::source { "dropbox-squeeze":
        location    => "http://linux.dropbox.com/debian/",
        release     => "squeeze",
        repos       => "main",
        key         => "5044912E",
        key_server  => "keyserver.ubuntu.com",
        include_src => false,
        before      => Package['nodejs'],
      }
    }
    if ! defined(Package['nodejs']) {
      package { 'nodejs':
        ensure => installed
      }
    }
    if ! defined(Package['curl']) {
      package { 'curl':
        ensure => installed
      }
    }
    
    file {$dropbox::config::dx_home:
        ensure => "directory",
        owner => $dropbox::config::dx_uid,
        group => $dropbox::config::dx_gid,
        mode => "755"
    }
    
    file { 'authorize.js':
      path      => "${dropbox::config::dx_home}/authorize.js",
      source    => 'puppet:///modules/dropbox/authorize.js',
      owner     => $dropbox::config::dx_uid,
      require => file [$dropbox::config::dx_home]
    }

    # kill dropbox if we need to run the authorization process
    exec { 'kill dropbox':
      command => 'service dropbox stop',
      unless  => "test -f ${dropbox::config::dx_home}/.dropbox/sigstore.dbx",
      before  => Exec['authorize-dropbox-user']
    }

    exec { 'authorize-dropbox-user':
      command => "node ${dropbox::config::dx_home}/authorize.js ${dropbox::config::user} ${dropbox::config::password}",
      user    => $dropbox::config::dx_uid,
      group   => $dropbox::config::dx_gid,
      cwd     => $dropbox::config::dx_home,
      logoutput => true,
      environment => ["HOME=${dropbox::config::dx_home}", "USER=${dropbox::config::dx_uid}"],
      creates => "${dropbox::config::dx_home}/.dropbox/sigstore.dbx",
      before  => Service['dropbox'],
      require => [File['authorize.js'], Package['nodejs'], Package['curl']]
    }
  }

  exec { 'download-dropbox':
    command => "wget -O /tmp/dropbox.tar.gz \"http://www.dropbox.com/download/?plat=lnx.${download_arch}\"",
    unless => "test -d ~${dropbox::config::dx_uid}/.dropbox-dist",
    require => User[$dropbox::config::dx_uid],
  }
  exec { 'install-dropbox':
    command => "tar -zxvf /tmp/dropbox.tar.gz -C ~${dropbox::config::dx_uid}",
    unless => "test -d ~${dropbox::config::dx_uid}/.dropbox-dist",
    require => Exec['download-dropbox'],
  }
  file { '/tmp/dropbox.tar.gz':
    ensure  => 'absent',
    require => Exec['install-dropbox'],
  }

  file { '/etc/init.d/dropbox':
    source => "puppet:///modules/dropbox/etc/init.d/dropbox.${::operatingsystem}",
    owner  => root,
    group  => root,
    mode   => 755,
  }
}
