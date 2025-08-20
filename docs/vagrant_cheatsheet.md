# 🧰 Vagrant Cheat Sheet

## 🟢 Basic Commands

| Command                        | Description                                                               |
|-------------------------------|---------------------------------------------------------------------------|
| `vagrant init`                | Creates an empty `Vagrantfile` in the current directory                   |
| `vagrant up`                  | Starts & provisions the VM(s) according to `Vagrantfile`                 |
| `vagrant ssh`                 | Connects you via SSH to the default VM (or: `vagrant ssh NAME`)          |
| `vagrant halt`                | Shuts down the VM(s) gracefully                                           |
| `vagrant destroy`             | Deletes the VM(s) completely (including disk)                             |
| `vagrant reload`              | Restarts the VM(s) (for configuration changes)                            |
| `vagrant reload --provision` | Restart **including provisioning** (e.g. `scripts/server.sh`)            |
| `vagrant suspend`             | Freezes the VM(s) (like "Pause")                                         |
| `vagrant resume`              | Brings the VM(s) back from "Pause" state                                  |
| `vagrant status`              | Shows status of all VMs in the current project                            |
| `vagrant global-status`       | Shows all Vagrant VMs system-wide                                         |

## 🧠 Provisioning & Debugging

| Command                                  | Description                                                  |
|------------------------------------------|--------------------------------------------------------------|
| `vagrant provision`                      | Only the provisioning (i.e. `server.sh`, `worker.sh`, ...) |
| `vagrant ssh-config`                     | Shows SSH data for manual login with `ssh`                  |
| `vagrant up --debug`                     | Start with verbose debug output                              |
| `vagrant destroy -f`                     | Destroys the VM **without confirmation** – useful for testing |

## 🔌 Synced Folders & Networks

| Command/Action                                    | Explanation                                                 |
|---------------------------------------------------|-------------------------------------------------------------|
| `config.vm.synced_folder "." "/vagrant"`          | Shared Folder: Host → Guest                                |
| `config.vm.network "public_network"`              | Bridged Network → real IP from host network                |
| `config.vm.network "private_network", ip: ...`    | Host-Only Network → fixed IP                               |
| `VBoxManage list bridgedifs`                      | Available network interfaces (for Bridged mode)            |

## 📁 Example File Structure

```
inception-of-things/
├── Vagrantfile
└── scripts/
    ├── server.sh
    └── worker.sh
```

## 💡 Pro Tips

- Always use `chmod +x scripts/*.sh` after changes
- Use `vagrant reload --provision` after changes in `scripts/`
- Define multiple VMs with `config.vm.define "name"`
- Use `vagrant ssh <name>` for targeted access

## ✨ Bonus: Working with Names

If you define VMs in your `Vagrantfile` like this:

```ruby
config.vm.define "ohoroS" do |server| ... end
config.vm.define "ohoroSW" do |worker| ... end
```

Then you can:

```bash
vagrant up ohoroS
vagrant ssh ohoroSW
vagrant halt ohoroS
```
