.PHONY: p1-up p1-verify p1-destroy p2-up p2-verify p2-resources p2-destroy

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

