# Puppet equivalent of ansible/provision.yml: prepare an Amazon Linux 2023
# host as a CI/CD deployment target. Apply locally on the node:
#
#   sudo dnf install -y puppet
#   sudo puppet apply puppet/manifests/site.pp
#
# Per-deploy steps stay in the CodeDeploy hooks under scripts/.

$aws_region = 'us-east-1'
$xray_rpm = $facts['os']['architecture'] ? {
  'aarch64' => 'aws-xray-daemon-3.x.arm64.rpm',
  default   => 'aws-xray-daemon-3.x.rpm',
}

package { ['ruby', 'wget', 'amazon-cloudwatch-agent']:
  ensure => installed,
}

exec { 'nodesource-repo':
  command => '/usr/bin/bash -c "curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -"',
  creates => '/etc/yum.repos.d/nodesource-nodistro.repo',
}

package { 'nodejs':
  ensure  => installed,
  require => Exec['nodesource-repo'],
}

exec { 'install-pm2':
  command => '/usr/bin/npm install -g pm2',
  creates => '/usr/bin/pm2',
  require => Package['nodejs'],
}

exec { 'download-codedeploy-installer':
  command => "/usr/bin/wget -q https://aws-codedeploy-${aws_region}.s3.${aws_region}.amazonaws.com/latest/install -O /tmp/codedeploy-install",
  creates => '/opt/codedeploy-agent',
  require => Package['ruby', 'wget'],
}

exec { 'install-codedeploy-agent':
  command => '/usr/bin/bash -c "chmod +x /tmp/codedeploy-install && /tmp/codedeploy-install auto"',
  creates => '/opt/codedeploy-agent',
  require => Exec['download-codedeploy-installer'],
}

service { 'codedeploy-agent':
  ensure  => running,
  enable  => true,
  require => Exec['install-codedeploy-agent'],
}

exec { 'install-xray-daemon':
  command => "/usr/bin/dnf install -y https://s3.us-east-2.amazonaws.com/aws-xray-assets.us-east-2/xray-daemon/${xray_rpm}",
  creates => '/usr/bin/xray',
}

service { 'xray':
  ensure  => running,
  enable  => true,
  require => Exec['install-xray-daemon'],
}
