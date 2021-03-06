# Makefile for CP/FPMD

include	../make.sys

# location of needed modules
MODFLAGS= $(MOD_FLAG)../iotk/src $(MOD_FLAG)../Modules \
          $(MOD_FLAG)../EE $(MOD_FLAG).

FOBJS = \
atoms_type.o \
berryion.o \
bforceion.o \
cg.o \
cg_sub.o \
cglib.o \
chargedensity.o \
cp_autopilot.o \
cp_emass.o \
cp_fpmd.o \
cp_interfaces.o \
cp_restart.o \
cplib.o \
cpr_mod.o \
cpr.o \
cprsub.o \
dealloc.o \
dforceb.o \
efermi.o \
efield.o \
eigs0.o \
electrons.o \
ensemble_dft.o \
exch_corr.o \
fft.o \
forces.o \
fromscra.o \
gradrho.o \
gtable.o \
init.o \
init_run.o \
inner_loop_cold.o \
input.o \
ions_positions.o \
ksstates.o \
mainvar.o \
main_loops.o \
cplib_meta.o \
metaxc.o \
modules.o \
move_electrons.o \
nl_base.o \
nlcc.o \
ortho_base.o \
ortho.o \
path_routines.o \
phasefactor.o \
polarization.o \
potentials.o \
pres_ai_mod.o \
print_out.o \
problem_size.o \
pseudo_base.o \
pseudopot.o \
pseudopot_sub.o \
qmatrixd.o \
qqberry.o \
read_pseudo.o \
restart.o \
restart_sub.o \
runcp.o \
spline.o \
stop_run.o \
stress.o \
vanderwaals.o \
vol_clu.o \
wannier_base.o \
wannier.o \
wave.o \
wave_types.o \
wf.o \
makov_payne.o

LOBJS = \
entropy.o 

QEMODS=../Modules/libqemod.a

TLDEPS= bindir mods libs libiotk

all : cp
cp : tldeps libcp.a cp.x cppp.x

cp.x : cprstart.o compute_fes_grads.o compute_scf.o libcp.a $(QEMODS) $(LIBOBJS)
	$(LD) $(LDFLAGS) -o cp.x cprstart.o compute_fes_grads.o compute_scf.o \
		libcp.a $(QEMODS) $(LIBOBJS) $(LIBS)
	- ( cd ../bin ; ln -fs ../CPV/cp.x . )

libcp.a : $(FOBJS) $(LOBJS) 
	 $(AR) $(ARFLAGS) $@ $?
	 $(RANLIB) $@

cp_version.o : cpver.h

cpver.h :
	echo "CHARACTER(LEN=70), PARAMETER :: version_date = '"`date`"'" \
		> cpver.h

cppp.x : fpmdpp.o $(QEMODS) $(LIBOBJS)
	$(LD) $(LDFLAGS) -o cppp.x fpmdpp.o $(QEMODS) $(LIBOBJS) $(LIBS)
	- (cd ../bin ; ln -fs ../CPV/cppp.x . )

tldeps:
	test -n "$(TLDEPS)" && ( cd .. ; $(MAKE) $(MFLAGS) $(TLDEPS) || exit 1) || :

clean :
	- /bin/rm -f cppp.x *.o *.mod cpver.h *.i core* *.F90 fort* \
		*.cpp *.d *.L *.a *.s cp.x

include make.depend
