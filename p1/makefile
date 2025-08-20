
.PHONY: p1 fclean

# Check versions and run setup for Part 1
p1:
	@echo "\033[1;34m[INFO] Checking VirtualBox version...\033[0m"
	@vboxmanage --version || echo "VirtualBox not found!"
	@echo "\033[1;34m[INFO] Checking Vagrant version...\033[0m"
	@vagrant --version || echo "Vagrant not found!"
	@echo "\033[1;33m[INFO] Removing KVM modules (requires sudo)...\033[0m"
	@sudo rmmod kvm_intel || true
	@sudo rmmod kvm || true
	@echo "\033[1;32m[INFO] Starting Vagrant...\033[0m"
	@vagrant up

# Destroy and clean .vagrant and config files
fclean:
	@echo "\033[1;31m[INFO] Destroying Vagrant VM...\033[0m"
	@vagrant destroy -f || true
	@echo "\033[1;31m[INFO] Removing .vagrant directory and config files...\033[0m"
	@rm -rf .vagrant token server-ip
