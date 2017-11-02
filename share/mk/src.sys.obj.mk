# $FreeBSD$
#
# Early setup of MAKEOBJDIR
#
# Default format is: /usr/obj/usr/src/[${TARGET}.${TARGET_ARCH}/]bin/sh
#  MAKEOBJDIRPREFIX is	/usr/obj
#  OBJROOT is		/usr/obj/usr/src/
#  OBJTOP is		/usr/obj/usr/src/[${TARGET}.${TARGET_ARCH}/]
#  MAKEOBJDIR is	/usr/obj/usr/src/[${TARGET}.${TARGET_ARCH}/]bin/sh
#
#  MAKEOBJDIRPREFIX will override the default pattern above and internally
#  set MAKEOBJDIR.  If OBJROOT is set then MAKEOBJDIRPREFIX is rooted inside
#  of there.
#
#  If MK_UNIFIED_OBJDIR is no then OBJROOT will always match OBJTOP.
#
#  If .MAKE.LEVEL == 0 then the TARGET.TARGET_ARCH is potentially added on.
#  If .MAKE.LEVEL >  0 and MAKEOBJDIRPREFIX is set then it will not get
#  TARGET.TARGET_ARCH added in as it assumes that MAKEOBJDIRPREFIX is
#  nested in the existing OBJTOP with TARGET.TARGET_ARCH in it.
#

_default_makeobjdirprefix?=	/usr/obj
_default_makeobjdir=	$${.CURDIR:S,^$${SRCTOP},$${OBJTOP},}

.include <bsd.mkopt.mk>

.if ${.MAKE.LEVEL} == 0 || empty(OBJROOT)
.if ${MK_UNIFIED_OBJDIR} == "no"
# Fall back to historical behavior.
# We always want to set a default MAKEOBJDIRPREFIX...
MAKEOBJDIRPREFIX?=	${_default_makeobjdirprefix}
# but don't enforce TARGET.TARGET_ARCH unless we're at the top-level directory.
.if ${.CURDIR} == ${SRCTOP} && \
    !(defined(TARGET) && defined(TARGET_ARCH) && \
    ${MACHINE} == ${TARGET} && ${MACHINE_ARCH} == ${TARGET_ARCH} && \
    !defined(CROSS_BUILD_TESTING))
MAKEOBJDIRPREFIX:=	${MAKEOBJDIRPREFIX}${TARGET:D/${TARGET}.${TARGET_ARCH}}
.endif
.endif	# ${MK_UNIFIED_OBJDIR} == "no"

.if !empty(MAKEOBJDIRPREFIX)
# put things approximately where they want
OBJROOT:=	${MAKEOBJDIRPREFIX}${SRCTOP}/
MAKEOBJDIRPREFIX=
# export but do not track
.export-env MAKEOBJDIRPREFIX
.endif
.if empty(MAKEOBJDIR)
# OBJTOP set below
MAKEOBJDIR=	${_default_makeobjdir}
# export but do not track
.export-env MAKEOBJDIR
# Expand for our own use
MAKEOBJDIR:=	${MAKEOBJDIR}
.endif
# SB documented at http://www.crufty.net/sjg/docs/sb-tools.htm
.if !empty(SB)
SB_OBJROOT?=	${SB}/obj/
# this is what we use below
OBJROOT?=	${SB_OBJROOT}
.endif
OBJROOT?=	${_default_makeobjdirprefix}${SRCTOP}/
.if ${OBJROOT:M*/} != ""
OBJROOT:=	${OBJROOT:H:tA}/
.else
OBJROOT:=	${OBJROOT:H:tA}/${OBJROOT:T}
.endif
# Must export since OBJDIR will dynamically be based on it
.export OBJROOT SRCTOP
.endif

.if ${MK_UNIFIED_OBJDIR} == "yes"
OBJTOP:=	${OBJROOT}${TARGET:D${TARGET}.${TARGET_ARCH}:U${MACHINE}.${MACHINE_ARCH}}
.else
# TARGET.TARGET_ARCH handled in OBJROOT already.
OBJTOP:=	${OBJROOT:H}
.endif	# ${MK_UNIFIED_OBJDIR} == "yes"

# Wait to validate MAKEOBJDIR until OBJTOP is set.
.if defined(MAKEOBJDIR)
.if ${MAKEOBJDIR:M/*} == ""
.error Cannot use MAKEOBJDIR=${MAKEOBJDIR}${.newline}Unset MAKEOBJDIR to get default:  MAKEOBJDIR='${_default_makeobjdir}'
.endif
.endif

# Fixup OBJROOT/OBJTOP if using MAKEOBJDIRPREFIX but leave it alone
# for DIRDEPS_BUILD which really wants to know the absolute top at
# all times.  This intenionally comes after adding TARGET.TARGET_ARCH
# so that is truncated away for nested objdirs.  This logic also
# will not trigger if the OBJROOT block above unsets MAKEOBJDIRPREFIX.
.if !empty(MAKEOBJDIRPREFIX) && ${MK_DIRDEPS_BUILD} == "no"
OBJTOP:=	${MAKEOBJDIRPREFIX}${SRCTOP}
OBJROOT:=	${OBJTOP}/
.endif

# Try to enable MK_AUTO_OBJ by default if we can write to the OBJROOT.  Only
# do this if AUTO_OBJ is not disabled by the user, not cleaning, and this
# is the first make ran.
.if ${.MAKE.LEVEL} == 0 && \
    ${MK_AUTO_OBJ} == "no" && empty(.MAKEOVERRIDES:MMK_AUTO_OBJ) && \
    !defined(WITHOUT_AUTO_OBJ) && !make(showconfig) && !make(print-dir) && \
    !defined(NO_OBJ) && \
    (${.TARGETS} == "" || ${.TARGETS:Nclean*:N*clean:Ndestroy*} != "")
# Find the last existing directory component and check if we can write to it.
# If the last component is a symlink then recurse on the new path.
CheckAutoObj= \
DirIsCreatable() { \
	[ -w "$${1}" ] && return 0; \
	d="$${1}"; \
	IFS=/; \
	set -- $${d}; \
	unset dir; \
	while [ $$\# -gt 0 ]; do \
		d="$${1}"; \
		shift; \
		if [ ! -d "$${dir}$${d}/" ]; then \
			if [ -L "$${dir}$${d}" ]; then \
				dir="$$(readlink "$${dir}$${d}")/"; \
				for d in "$${@}"; do \
					dir="$${dir}$${d}/"; \
				done; \
				ret=0; \
				DirIsCreatable "$${dir%/}" || ret=$$?; \
				return $${ret}; \
			else \
				break; \
			fi; \
		fi; \
		dir="$${dir}$${d}/"; \
	done; \
	[ -w "$${dir}" ]; \
}; \
CheckAutoObj() { \
	if DirIsCreatable "$${1}"; then \
		echo yes; \
	else \
		echo no; \
	fi; \
}
.if !empty(MAKEOBJDIRPREFIX)
WANTED_OBJDIR=	${MAKEOBJDIRPREFIX}${.CURDIR}
.else
WANTED_OBJDIR=	${MAKEOBJDIR}
.endif
OBJDIR_WRITABLE!= \
	${CheckAutoObj}; CheckAutoObj "${WANTED_OBJDIR}" || echo no
# Export the decision to sub-makes.
MK_AUTO_OBJ:=	${OBJDIR_WRITABLE}
.export MK_AUTO_OBJ
.elif make(showconfig)
# Need to export for showconfig internally running make -dg1.  It is enabled
# in sys.mk by default.
.export MK_AUTO_OBJ
.endif	# ${MK_AUTO_OBJ} == "no" && ...

# Assign this directory as .OBJDIR if possible after determining if AUTO_OBJ
# can be enabled by default.
.if ${MK_AUTO_OBJ} == "no"
# The expected OBJDIR already exists, set it as .OBJDIR.
.if !empty(MAKEOBJDIRPREFIX) && exists(${MAKEOBJDIRPREFIX}${.CURDIR})
.OBJDIR: ${MAKEOBJDIRPREFIX}${.CURDIR}
.elif exists(${MAKEOBJDIR})
.OBJDIR: ${MAKEOBJDIR}
# Special case to work around bmake bug.  If the top-level .OBJDIR does not yet
# exist and MAKEOBJDIR is passed into environment and yield a blank value,
# bmake will incorrectly set .OBJDIR=${SRCTOP}/ rather than the expected
# ${SRCTOP} to match ${.CURDIR}.
.elif ${MAKE_VERSION} <= 20170720 && \
    ${.CURDIR} == ${SRCTOP} && ${.OBJDIR} == ${SRCTOP}/
.OBJDIR: ${.CURDIR}
.endif
.endif	# ${MK_AUTO_OBJ} == "no"
