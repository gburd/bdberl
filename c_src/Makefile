# This Makefile builds the dependency (libdb) needed by bdberl_drv.so

TAR		?= tar
GUNZIP		?= gunzip
BDB_VER		:= 5.2.28
BDB_DIR    	:= $(CURDIR)/db-$(BDB_VER)

SYSTEM_DIR 	:= $(CURDIR)/system
LIB_DIR    	:= $(SYSTEM_DIR)/lib
INC_DIR    	:= $(SYSTEM_DIR)/include


db: $(LIB_DIR)/libdb.a

$(LIB_DIR)/libdb.a:
	$(GUNZIP) -c db-$(BDB_VER).tar.gz | $(TAR) xf -
	@for I in patches/*.patch; do \
		(patch -p0 < $${I} || echo "Skipping patch"); \
	done
	@./configure_bdb.sh $(BDB_DIR) $(SYSTEM_DIR)
	@$(MAKE) -C $(BDB_DIR)/build_unix install

clean:
	@rm -rf $(SYSTEM_DIR) $(BDB_DIR)

.EXPORT_ALL_VARIABLES:
