.PHONY: test
test: test.sle15_sp2

.PHONY: test.%
test.%:
	perl -I . rsync.pl --dry --add-existing --verbose $*
