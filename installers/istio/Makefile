test_variables:
ifndef ISTIO_VERSION
  $(info ISTIO_VERSION not set. Defaulting to latest release)
  ISTIO_VERSION=LATEST
endif


install: test_variables
	eval ./install.sh ${ISTIO_VERSION}
