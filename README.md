# Carta Drive

Carta Drive is based on innomatica's
[Carta Plus](https://github.com/innomatica/cartaplus), which is itself based on
[Carta](https://github.com/innomatica/carta) and adds a cloud bookshelf and
shared libraries.

Google sign-in and access to Carta Plus's cloud bookshelf no longer work. We
plan to store everything in Google Drive.

Information about the original project is in its
[README](https://github.com/innomatica/cartaplus/blob/master/README.md).

The [Carta manual](https://innomatica.github.io/carta/manual/) covers the
audiobook features.

## How to Build Your WebDAV Server

The easiest way is to use [Nextcloud](https://nextcloud.com/). You can use run 
your own server or you can use one of the 
[Nextcloud service prividers](https://nextcloud.com/partners/).

If you have a NAS, then you can spin up your WebDAV server using rclone or apache.

### Running RClone

```
rclone serve webdav --addr :8080 --user username --pass password /var/www/webdav
```

### Apache Settings

- `/etc/apache2/ports.conf`

```
Listen 80
# add port number of choice
Listen 8080
...
```

- `/etc/sites-available/your.domain.conf`

```
DavLockDB /usr/local/share/apache2/DavLock
<VirtualHost *:8080>
	ServerAdmin webmaster@localhost
	DocumentRoot /var/www/html

	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined

	Alias /webdav /var/www/webdav
	<Directory /var/www/webdav>
		DAV On
		AuthName "webdav"
		AuthType Basic
		AuthUserFile /usr/local/share/apache2/webdav-pass
		Require valid-user
	</Directory>
</VirtualHost>
```

- password files

```
sudo mkdir -p /usr/local/share/apache2
sudo htpasswd -c webdav-pass username
sudo chown www-data:www-data /usr/local/share/apache2/webdav-pass
```

- davloc directory

```
sudo mkdir -p /usr/local/share/apache2/DavLock
sudo chown www-data:www-data /usr/local/share/apache2/DavLock
```

- modules

```
a2enmod auth_basic dav dav_fs
```

- site

```
a2ensite your.domain
systemctl restart apache2
```

### References

- [How to Configure WebDav with Apache on Ubuntu 18.04](https://www.digitalocean.com/community/tutorials/how-to-configure-webdav-access-with-apache-on-ubuntu-18-04)
- [rclone serve webdav](https://rclone.org/commands/rclone_serve_webdav/)
