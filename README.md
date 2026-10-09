# Carta Drive

Carta Drive is based on innomatica's
[Carta Plus](https://github.com/innomatica/cartaplus) (which is itself based on
[Carta](https://github.com/innomatica/carta) and adds a cloud bookshelf and
shared libraries). Carta Drive stores the bookshelf in each reader's own Google
Drive account.
Information about the original project is in the
[original README](https://github.com/innomatica/cartaplus/blob/master/README.md).

## Using Carta Drive

When you first open Carta Drive, choose a Google account and allow access to
Google Drive. The app remembers that account until you sign out. It syncs your
bookshelf with Drive and opens the last synced copy when you are offline.
Previously downloaded audio remains available offline too.

Carta Drive does not request access to your entire Google Drive. Its permissions
cover a private area for its own data (`drive.appdata`) and files it creates or
you explicitly open with it (`drive.file`). It cannot browse your other files.

## Why Carta Drive exists

Carta Plus used Google accounts for sign-in and Firebase Firestore to store its
cloud bookshelf. Its sign-in and access to the original Firestore database no
longer work. Carta Drive uses its own Google sign-in configuration and keeps
your bookshelf in your own Google Drive account.

Books left in the original Firestore project are not imported automatically.

The [original Carta manual](https://innomatica.github.io/carta/manual/) covers
the audiobook features Carta Drive inherits from Carta Plus.

## Google Drive storage and offline use

Carta Drive stores books and WebDAV server settings in the private application
data area of your own Google Drive account. It syncs the bookshelf when signing
in and after edits. The saved bookshelf and previously downloaded audio remain
available offline. WebDAV usernames and passwords stay on the device and must
be entered again on each device.

If you choose to share a library from Settings, Carta Drive creates a separate
link-accessible file in your Google Drive. Anyone with that link can read that
library's book list. Shared libraries do not contain WebDAV credentials.

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
