.ONESHELL: # Applies to every targets in the file!

test_variables:
ifndef KIND_VERSION
	$(info KIND_VERSION not set. Defaulting to latest release)
	KIND_VERSION=LATEST
endif

ifndef ISTIO_VERSION
	$(info ISTIO_VERSION not set. Defaulting to latest release)
	ISTIO_VERSION=LATEST
endif

KIND_INSTALLER=installers/kind
ISTIO_INSTALLER=installers/istio

install: test_variables .kind_install .istio_install

cleanup: .kind_cleanup .sonarqube_cleanup

.kind_install:
	$(MAKE) -C ${KIND_INSTALLER} install

.istio_install:
	$(MAKE) -C ${ISTIO_INSTALLER} install

.kind_cleanup:
	$(MAKE) -C ${KIND_INSTALLER} cleanup
