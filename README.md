# Joruri Mail

Japan Originated Ruby-based RESTful and Integrated Mail

Joruri Mail is a browser-based IMAP client software.

## Features

* Simple and intuitive UI
* User customizable settings (filters, templates, signatures, labels and more)
* Multilingual mail decoding (especially japanese proper decoding)
* Drag and drop features (local files, mails and mailboxes)
* Secure structure due to not saving email body in application database
* Optimized UI for feature phone and smartphone
* Cooperation with [Joruri Gw](https://github.com/joruri/joruri-gw) (single sign-on, schedule registration)

## Demo

[http://joruri.org/demo/jorurimail/](http://joruri.org/demo/jorurimail/)

## System dependencies

* CentOS 7.2 x86_64 (recommended), CentOS 6.8 x86_64
* Apache 2.4 (recommended), Apache 2.2
* MySQL 5.6
* Ruby 2.3
* Rails 5.0
* SMTP, IMAP4

## Installation

Installation maunal assumes:

* CentOS is installed with minimal configuration
* SELinux is disabled
* Firewall is disabled

Make sure your environment is secure.

### Quick install

Install script was expired and removed from repository.

### Manual install

[doc/INSTALL.txt](doc/INSTALL.txt)

## IMAP capabilities

Following IMAP capabilities are supported:

* IMAP4REV1: [RFC2060](https://tools.ietf.org/html/rfc2060), [RFC3501](https://tools.ietf.org/html/rfc3501) (required)
* SORT: [RFC5256](https://tools.ietf.org/html/rfc5256) (recommended)
* QUOTA: [RFC2087](https://tools.ietf.org/html/rfc2087) (recommended)
* LIST-STATUS: [RFC5819](https://tools.ietf.org/html/rfc5819) (recommended)
* MOVE: [RFC6851](https://tools.ietf.org/html/rfc6851) (recommended)
* ESORT: [RFC5267](https://tools.ietf.org/html/rfc5267) (recommended)
* SPECIAL-USE: [RFC6154](https://tools.ietf.org/html/rfc6154) (not required)

## SMTP extensions

Following SMTP extensions are supported:

* Delivery Status Notification: [RFC3461](https://tools.ietf.org/html/rfc3461)

## Changelog

[doc/CHANGES.txt](doc/CHANGES.txt)

## DB Changelog

[doc/DB_CHANGES.txt](doc/DB_CHANGES.txt)

## License

GNU GENERAL PUBLIC LICENSE Version 3

[LICENSE](LICENSE)

Copyright (C) Tokushima Prefectural Government, IDS Inc., SiteBridge Inc.

[COPYING](COPYING)
