.PHONY: install link uninstall validate status test help

help:
	@echo "ODrive — Unified Cloud Drive Manager"
	@echo ""
	@echo "Usage:"
	@echo "  make install     Install plugin into ~/.config/omarchy and enable on bar"
	@echo "  make link        Install as symlink for active development"
	@echo "  make uninstall   Remove plugin and CLI from Omarchy"
	@echo "  make validate    Run omarchy-plugin-validate against manifest"
	@echo "  make status      Show status of cloud drives"
	@echo "  make clean       Clean up Python cache files"
	@echo ""

install:
	./install.sh --enable

link:
	./install.sh --link --enable

uninstall:
	./install.sh --uninstall

validate:
	@if command -v omarchy-plugin-validate >/dev/null 2>&1; then \
		omarchy-plugin-validate .; \
		echo "✓ Manifest and plugin structure valid"; \
	else \
		echo "omarchy-plugin-validate not found, skipping validation"; \
	fi

status:
	odrive status

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	rm -rf build/ dist/ *.egg-info
