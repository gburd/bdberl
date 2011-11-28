# This Makefile builds the dependency (libdb) needed by bdberl_drv.so

ERL             ?=erl
ERL_FLAGS       ?=+A10
TAR		?= tar
GUNZIP		?= gunzip
BDB_VER		:= 5.2.36
BDB_DIR    	:= $(CURDIR)/db-$(BDB_VER)
BDB_DIST        := db-$(BDB_VER).tar.gz
#BDB_DIST_URL    := http://download.oracle.com/berkeley-db/$(BDB_DIST)
BDB_DIST_URL    := https://github.com/downloads/gburd/libdb/$(BDB_DIST)

SYSTEM_DIR 	:= $(CURDIR)/system
LIB_DIR    	:= $(SYSTEM_DIR)/lib
INC_DIR    	:= $(SYSTEM_DIR)/include


db: $(LIB_DIR)/libdb.a

$(LIB_DIR)/libdb.a: $(BDB_DIST)
	$(GUNZIP) -c db-$(BDB_VER).tar.gz | $(TAR) xf -
	@for I in patches/*.patch; do \
		(patch -p0 < $${I} || echo "Skipping patch"); \
	done
	@./configure_bdb.sh $(BDB_DIR) $(SYSTEM_DIR)
	@$(MAKE) -C $(BDB_DIR)/build_unix install

clean:
	@rm -rf ./*.o $(SYSTEM_DIR) $(BDB_DIR)

$(BDB_DIST):
	$(REBAR_FETCH) $(BDB_DIST_URL)

.EXPORT_ALL_VARIABLES:
