.PHONY: p1-up p1-verify p1-destroy \
	p2-up p2-verify p2-resources p2-destroy \
	p3-install p3-up p3-verify p3-status p3-destroy \
	bonus-install bonus-up bonus-verify bonus-status bonus-destroy

p1-up:
	$(MAKE) -C p1 up

p1-verify:
	$(MAKE) -C p1 verify

p1-destroy:
	$(MAKE) -C p1 destroy

p2-up:
	$(MAKE) -C p2 up

p2-verify:
	$(MAKE) -C p2 verify

p2-resources:
	$(MAKE) -C p2 resources

p2-destroy:
	$(MAKE) -C p2 destroy

p3-install:
	$(MAKE) -C p3 install

p3-up:
	$(MAKE) -C p3 up

p3-verify:
	$(MAKE) -C p3 verify

p3-status:
	$(MAKE) -C p3 status

p3-destroy:
	$(MAKE) -C p3 destroy

bonus-install:
	$(MAKE) -C bonus install

bonus-up:
	$(MAKE) -C bonus up

bonus-verify:
	$(MAKE) -C bonus verify

bonus-status:
	$(MAKE) -C bonus status

bonus-destroy:
	$(MAKE) -C bonus destroy

