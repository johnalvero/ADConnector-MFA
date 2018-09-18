$token_enckey_location		= "s3://<bucket>/<path>/encKey"
$audit_privatekey_location      = "s3://<bucket>/private.pem"
$audit_publickey_location       = "s3://<bucket>/public.pem"
$db_host			= "localhost"
$db_port			= "3306"
$db_user			= "linotp"
$db_pass			= "<DB-Password"
$db_name			= "LINOTP"
$admin_digest_user      	= "<admin-user>"
$admin_digest_password  	= "<admin-password>"
$realm				= "<realm>"

$radius_clients = {
    'localhost' => {
        'ipaddr'  => '127.0.0.1',
        'netmask' => '32',
        'secret'  => '<your-secret>',
    },

    'adconnector' => {
        'ipaddr'  => '10.0.0.0',
        'netmask' => '16',
        'secret'  => '<your-secret>',
    },
}



##### No configuration below this line #####

$linotp_conf_template = @(END)
[server:main]
use = egg:Paste#http
host = 0.0.0.0
port = 5001

[DEFAULT]
debug = false
profile = false
smtp_server = localhost
error_email_from = paste@localhost
linotpAudit.type = linotp.lib.audit.SQLAudit
linotpAudit.sql.url = mysql://<%= $tmpl_db_user %>:<%= $tmpl_db_pass %>@<%= $tmpl_db_host %>:<%= $tmpl_db_port %>/<%= $tmpl_db_name %>
linotpAudit.key.private = %(here)s/private.pem
linotpAudit.key.public = %(here)s/public.pem
linotpAudit.sql.highwatermark = 10000
linotpAudit.sql.lowwatermark = 5000
linotp.DefaultSyncWindow = 1000
linotp.DefaultOtpLen = 6
linotp.DefaultCountWindow = 50
linotp.DefaultMaxFailCount = 15
linotp.FailCounterIncOnFalsePin = True
linotp.PrependPin = True
linotp.DefaultResetFailCount = True
linotp.splitAtSign = True
linotpGetotp.active = False
linotpSecretFile = %(here)s/encKey
radius.dictfile= %(here)s/dictionary
radius.nas_identifier = LinOTP

[app:main]
use = egg:LinOTP
alembic.ini = %(here)s/alembic.ini
sqlalchemy.url = mysql://<%= $tmpl_db_user %>:<%= $tmpl_db_pass %>@<%= $tmpl_db_host %>:<%= $tmpl_db_port %>/<%= $tmpl_db_name %>
sqlalchemy.pool_recycle = 3600
who.config_file = %(here)s/who.ini
who.log_level = warning
who.log_file = /var/log/linotp/linotp.log
full_stack = true
static_files = true
cache_dir = %(here)s/data
custom_templates = %(here)s/custom-templates/

[loggers]
keys = root

[logger_root]
level = WARN
handlers = file

[handlers]
keys = file

[handler_file]
class = handlers.RotatingFileHandler
args = ('/var/log/linotp/linotp.log','a', 10000000, 4)
level = WARN
formatter = generic

[formatters]
keys = generic

[formatter_generic]
format = %(asctime)s %(levelname)-5.5s [%(name)s][%(funcName)s #%(lineno)d] %(message)s
datefmt = %Y/%m/%d - %H:%M:%S
END

$radius_client_conf_template = @(END)
<% $radius_clients.each |$element, $element_value| { -%>
client <%= $element %> {
<% $element_value.each |$key, $value| { %>      <%= $key -%> = <%= $value %>
<% } %>
} 

<% } -%>
END

$linotp_perl_module_template = @(END)
perl {
     filename = /usr/share/linotp/radius_linotp.pm
}
END

$perl_module_config_template = @(END)
URL=https://localhost/validate/simplecheck
REALM=<%= $realm %>
Debug=True
SSL_CHECK=False
END


$linotp_main_config_template = @(END)
server default {

listen {
	type = auth
	ipaddr = *
	port = 0

	limit {
	      max_connections = 16
	      lifetime = 0
	      idle_timeout = 30
	}
}

listen {
	ipaddr = *
	port = 0
	type = acct
}



authorize {
        preprocess
        IPASS
        suffix
        ntdomain
        files
        expiration
        logintime
        update control {
                Auth-Type := Perl
        }
        pap
}

authenticate {
	Auth-Type Perl {
		perl
	}
}


preacct {
	preprocess
	acct_unique
	suffix
	files
}

accounting {
	detail
	unix
	-sql
	exec
	attr_filter.accounting_response
}


session {

}


post-auth {
	update {
		&reply: += &session-state:
	}

	-sql
	exec
	remove_reply_message_if_eap
}
}
END


$http_ssl_linotp = @(END)
WSGISocketPrefix run/wsgi

Listen 443
SSLPassPhraseDialog  builtin
SSLSessionCache         shmcb:/var/cache/mod_ssl/scache(512000)
SSLSessionCacheTimeout  300
SSLRandomSeed startup file:/dev/urandom  256
SSLRandomSeed connect builtin
SSLCryptoDevice builtin

<VirtualHost _default_:443>
    ServerAdmin webmaster@localhost

#    Include /etc/linotp2/apache-servername.conf

    Header always edit Set-Cookie ^(.*)$ $1;secure

    <Directory />
        AllowOverride None
        Require all denied
    </Directory>

    <Directory /etc/linotp2>
        <Files linotpapp.wsgi>
           Require all granted
        </Files>
    </Directory>

    <Directory /usr/share/doc/linotpdoc/html>
        Require all granted
    </Directory>

    Alias /doc/html         /usr/share/doc/linotpdoc/html

    WSGIScriptAlias /       /etc/linotp2/linotpapp.wsgi
    #
    # The daemon is running as user 'linotp'
    # This user should have access to the encKey database encryption file
    WSGIDaemonProcess linotp processes=1 threads=15 display-name=%{GROUP} user=linotp
    WSGIProcessGroup linotp
    WSGIPassAuthorization On


    <LocationMatch /ocra/(request|checkstatus|getActivationCode|calculateOtp)>
        AuthType Digest
        AuthName "LinOTP2 admin area"
        AuthDigestProvider file
        AuthUserFile /etc/linotp2/admins
        Require valid-user
    </LocationMatch>


    <LocationMatch /(audit|manage|system|license|admin)>
        AuthType Digest
        AuthName "LinOTP2 admin area"
        AuthDigestProvider file
        AuthUserFile /etc/linotp2/admins
        Require valid-user
        #----------------------------------------
        # Here we do client certificate auth
        #----------------------------------------
        # SSLVerifyClient require
        # SSLVerifyDepth  2
        # # Who signed the client certificates
        # SSLCACertificateFile /etc/ssl/certs/ca.crt
        # # what client certs are allowed to log in?
        # SSLRequire ( %{SSL_CLIENT_S_DN_OU} eq "az" and %{SSL_CLIENT_S_DN_CN} in {"linotpadm", "Manfred Mann"} )
    </LocationMatch>

    <Location /gettoken>
        AuthType Digest
        AuthName "LinOTP2 gettoken"
        AuthDigestProvider file
        AuthUserFile /etc/linotp2/gettoken-api
        Require valid-user
    </Location>

    <Location /selfservice>
        # The authentication for selfservice is done from within the application
    </Location>

    <Location /validate>
        # No Authentication
    </Location>


    ErrorLog /var/log/httpd/error_log

    LogLevel warn

    # Do not use %q! This will reveal all parameters, including setting PINs and Keys!
    # Using SSL_CLINET_S_DN_CN will show you, which administrator did what task
    LogFormat "%h %l %u %t %>s \"%m %U %H\"  %b \"%{Referer}i\" \"%{User-agent}i\" \"%{SSL_CLIENT_S_DN_CN}x\"" LinOTP2
    CustomLog /var/log/httpd/ssl_access_log LinOTP2

    #   SSL Engine Switch:
    #   Enable/Disable SSL for this virtual host.
    SSLEngine on

    #   If both key and certificate are stored in the same file, only the
    #   SSLCertificateFile directive is needed.
SSLProtocol all -SSLv2

SSLHonorCipherOrder on
SSLCipherSuite ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS:!aNULL:!eNUL:!MD5:!RC4:!DES:!LOW:!EXP 

SSLCertificateFile /etc/pki/tls/certs/localhost.crt
SSLCertificateKeyFile /etc/pki/tls/private/localhost.key

    <FilesMatch "\.(cgi|shtml|phtml|php)$">
        SSLOptions +StdEnvVars
    </FilesMatch>

    <Directory /usr/lib/cgi-bin>
        SSLOptions +StdEnvVars
    </Directory>

    BrowserMatch ".*MSIE.*" \
        nokeepalive ssl-unclean-shutdown \
        downgrade-1.0 force-response-1.0

    ErrorDocument 500 "<h1>Internal Server Error</h1> Possible reasons can be missing modules or bad access rights on LinOTP configuration files or log files. Please check the apache logfile <pre>/var/log/httpd/error_log</pre> for more details."

</VirtualHost>
END


class linotp {

	exec { 'linotp_repo':
		command		=> "/usr/bin/yum -y localinstall http://linotp.org/rpm/el7/linotp/x86_64/Packages/LinOTP_repos-1.1-1.el7.x86_64.rpm",
		creates		=> '/etc/yum.repos.d/linotp.repo'
	}

	package { 'linotp_package':
		name		=> "LinOTP",
		ensure		=> present,
		allow_virtual 	=> false,
		require 	=> Exec['linotp_repo']
	}

	package { 'linotp_package_apache':
        	name    	=> "LinOTP_apache",
		ensure  	=> present,
		allow_virtual 	=> false,
		require 	=> Package['linotp_package']
   	}

 	package {'yum-plugin-versionlock':
		ensure 		=> present,
		allow_virtual 	=> false,
	}

	exec { 'lock_python-repoze-who':
		command 	=> '/usr/bin/yum versionlock python-repoze-who',
		unless  	=> '/usr/bin/yum versionlock list | /usr/bin/grep python-repoze-who 2>&1 >> /dev/null',
		require 	=> Package['yum-plugin-versionlock'],
	}

	file { 'absent_ssl_default_config':
		path 		=> "/etc/httpd/conf.d/ssl.conf",
		ensure 		=> absent,
		require 	=> Package['linotp_package_apache'],
	}

	file { 'apache_linotp_config':
		path  		=> '/etc/httpd/conf.d/ssl_linotp.conf',
		ensure 		=> file,
		require 	=> Package['linotp_package_apache'],
		content 	=> inline_epp($http_ssl_linotp),
	}

	file { 'linotp_ini':
		ensure 		=> file,
		path		=> "/etc/linotp2/linotp.ini",
		content		=> inline_epp($linotp_conf_template, {'tmpl_db_user' => $db_user,'tmpl_db_pass' => $db_pass, 'tmpl_db_host' => $db_host, 'tmpl_db_port' => $db_port, 'tmpl_db_name' => $db_name}),
 		require 	=> Package['linotp_package'],
	}

        package { 'awscli':
                ensure          => present,
                allow_virtual   => false,
        }
	
	exec { 'encKey':
		command 	=> "/usr/bin/aws s3 cp $token_enckey_location /etc/linotp2/encKey && /usr/bin/chmod 640 /etc/linotp2/encKey &&  /usr/bin/chown linotp.root /etc/linotp2/encKey",
		creates 	=> "/etc/linotp2/encKey",
		require         => Package['awscli'],
	}
	
	# Realm is hard-coded for now because its also hard-coded in the apache config
	$pwdigest  = "$admin_digest_user:LinOTP2 admin area:$admin_digest_password".md5
    	$htcontent = "$admin_digest_user:LinOTP2 admin area:$pwdigest"

	file { 'htpasswd_admin':
		path		=> "/etc/linotp2/admins",
		content 	=> $htcontent,
		mode		=> 0640,
		owner		=> "linotp",
		group		=> "apache",
	}

	exec { 'audit_private':
                command         => "/usr/bin/aws s3 cp $audit_privatekey_location /etc/linotp2/private.pem && /usr/bin/chmod 640 /etc/linotp2/private.pem &&  /usr/bin/chown root.apache /etc/linotp2/private.pem",
                creates         => "/etc/linotp2/private.pem",
		require		=> Package['linotp_package_apache'],
        }

        exec { 'audit_public':
                command         => "/usr/bin/aws s3 cp $audit_publickey_location /etc/linotp2/public.pem && /usr/bin/chmod 640 /etc/linotp2/public.pem &&  /usr/bin/chown root.apache /etc/linotp2/public.pem",
                creates         => "/etc/linotp2/public.pem",
		require         => Package['linotp_package_apache'],
        }
	

	service { 'httpd':
		ensure 		=> running,
		name 		=> httpd,
		enable 		=> true,
		subscribe 	=> [File['apache_linotp_config'], File['linotp_ini']]
	}

}


class freeradius {
	$required_packages = ['freeradius', 'freeradius-perl', 'freeradius-utils', 'perl-App-cpanminus', 'perl-LWP-Protocol-https', 'perl-Try-Tiny', 'MySQL-python']
	package { $required_packages:
		ensure		=> present,
		allow_virtual 	=> false,
	}

	file { 'raddb_clients_conf':
		ensure      	=> file,
		path        	=> "/etc/raddb/clients.conf",
		content     	=> inline_epp($radius_client_conf_template, $radius_clients),
		owner		=> root,
		group		=> radiusd,
		mode		=> 0640,
		require		=> Package[$required_packages],
    }

	exec { 'linotp_perl_module':
		command		=> "/usr/bin/curl -so /usr/share/linotp/radius_linotp.pm https://raw.githubusercontent.com/LinOTP/linotp-auth-freeradius-perl/master/radius_linotp.pm && /bin/chmod 755 /usr/share/linotp/radius_linotp.pm",
		creates		=> "/usr/share/linotp/radius_linotp.pm",
		require     	=> Package[$required_packages],
	}

	file { 'linotp_perl_module_file':
		ensure		=> file,
		path		=> "/etc/raddb/mods-available/perl",
		content		=> inline_epp($linotp_perl_module_template),
		owner   	=> root,
		group   	=> radiusd,
		mode    	=> 0640,
		require 	=> Package[$required_packages],
	}

	file { '/etc/raddb/mods-enabled/perl':
		ensure		=> 'link',
		target		=> '/etc/raddb/mods-available/perl',
		require 	=> File['linotp_perl_module_file'],

	}

	file { '/etc/linotp2/rlm_perl.ini':
		ensure		=> file,
		content		=> inline_epp($perl_module_config_template, {'realm' => $realm}),
		owner   	=> linotp,
		group   	=> root,
		mode    	=> 0644,
		require 	=> Package[$required_packages],
	}

	file { '/etc/raddb/sites-enabled/inner-tunnel':
		ensure		=> absent,
		require 	=> Package[$required_packages],
	}

	file { '/etc/raddb/sites-enabled/default':
		ensure  	=> absent,
		require 	=> Package[$required_packages],
	}

	file { '/etc/raddb/mods-enabled/eap':
        	ensure  	=> absent,
        	require 	=> Package[$required_packages],
	}

	file { '/etc/raddb/sites-available/linotp':
		ensure		=> file,
		content		=> inline_epp($linotp_main_config_template),
		owner   	=> root,
		group   	=> radiusd,
		mode    	=> 0640,
		require 	=> Package[$required_packages],
	}

	file { '/etc/raddb/sites-enabled/linotp':
        	ensure  	=> 'link',
        	target  	=> '/etc/raddb/sites-available/linotp',
        	require 	=> Package[$required_packages],
	}

	file { '/etc/raddb/users':
		ensure		=> absent,
		require         => Package[$required_packages],
	}

	exec { 'install_Config-File':
		command		=> "/bin/cpanm Config::File",
		creates		=> "/usr/local/share/perl5/Config/File.pm",
		require		=> Package[$required_packages],
	}

	service { 'radiusd':
		ensure 			=> running,
		name 			=> radiusd,
		enable 			=> true,
		subscribe 		=> [File['/etc/raddb/sites-available/linotp'], File['/etc/linotp2/rlm_perl.ini'], File['raddb_clients_conf'], File['/etc/raddb/users']],
	}
}

include linotp
include freeradius
