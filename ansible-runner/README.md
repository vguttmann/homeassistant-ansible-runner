# Ansible Runner Add-on: Execute playbooks through Home Assistant

The only constant and 100% reliable part in my Homelab has been Home Assistant, so I decided to use it to execute the playbooks that configure the rest of my home lab through it.

# SSH Keys

The SSH keys to deploy with Ansible need to be added to the deployment keys, the same keys are also used for authenticating to your git server via SSH.
Unlike the Git Pull plugin, you can just copy your whole private key and paste it in as one. It will almost certainly break the formatting of the page, but there are no problems with missing/stripped newlines.

# Ansible Vault

The secret to the relevant Ansible vault needs to be entered as text in the UI, from there it will get put into a local file. Using custom files in git is not supported as of now

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armhf Architecture][armhf-shield]
![Supports armv7 Architecture][armv7-shield]
![Supports i386 Architecture][i386-shield]

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armhf-shield]: https://img.shields.io/badge/armhf-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
[i386-shield]: https://img.shields.io/badge/i386-yes-green.svg
