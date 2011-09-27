
# check for one particular file of the sources 
AC_INIT([ocaml-xmlplaylist],[0.1.3],[savonet-users@lists.sourceforge.net])

VERSION=$PACKAGE_VERSION
AC_SUBST(VERSION)
AC_MSG_RESULT([configuring $PACKAGE_STRING])

AC_BASE_CHECKS()

#
# Xmlm
#

AC_MSG_CHECKING(for xmlm)
   if ! $OCAMLFIND query xmlm > /dev/null 2>&1 ; then
       AC_MSG_ERROR(Not found.)
   else
   INC="$INC `$OCAMLFIND query xmlm`"
   requires="$requires xmlm"
   AC_MSG_RESULT(ok)
fi

# substitutions to perform
AC_SUBST(VERSION)
AC_SUBST(INC)
AC_SUBST(requires)

# Finally create the Makefile and samples
AC_CONFIG_FILES([Makefile],[chmod a-w Makefile])
AC_CONFIG_FILES([src/META])
AC_CONFIG_FILES([src/Makefile])
AC_OUTPUT
