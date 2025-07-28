test_variables:
ifndef KIND_VERSION
  $(info KIND_VERSION not set. Defaulting to latest release)
  KIND_VERSION=LATEST
endif
ifndef CLEAN
  $(info CLEAN not set. Defaulting to RETAIN)
  CLEAN=FALSE
endif

install: test_variables
	eval ./install.sh ${KIND_VERSION} ${CLEAN}

cleanup:
	eval ./cleanup.sh