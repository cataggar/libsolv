/*
 * Copyright (c) 2026 GitHub, Inc.
 *
 * This program is licensed under the BSD license, read LICENSE.BSD
 * for further information
 */

#include <stdio.h>
#include <string.h>

#include "evr.h"
#include "pool.h"
#include "repo.h"
#include "solvversion.h"

#ifdef ENABLE_DEBIAN
#include "repo_deb.h"
#endif

static int
check(int condition, const char *message)
{
  if (condition)
    return 0;
  fprintf(stderr, "%s\n", message);
  return 1;
}

int
main(void)
{
  Pool *pool = pool_create();
  int failed = 0;

#ifdef DEBIAN
  failed |= check(pool->disttype == DISTTYPE_DEB, "Debian build did not select Debian distribution semantics");
  failed |= check(pool_evrcmp_str(pool, "1+1", "1.1", EVRCMP_COMPARE) < 0,
                  "Debian version ordering did not distinguish '+' from '.'");
#else
  failed |= check(pool->disttype == DISTTYPE_RPM, "default build no longer selects RPM distribution semantics");
  failed |= check(pool_evrcmp_str(pool, "1+1", "1.1", EVRCMP_COMPARE) == 0,
                  "default build no longer uses RPM version ordering");
#endif

#ifdef ENABLE_DEBIAN
#ifndef LIBSOLVEXT_FEATURE_DEBIAN
  failed |= check(0, "solvversion.h does not declare Debian repository support");
#else
  {
    static const char packages[] =
      "Package: hello\n"
      "Version: 1:2.0~rc1-1\n"
      "Architecture: amd64\n"
      "Depends: libc6 (>> 2.34)\n"
      "Description: loader smoke test\n";
    FILE *fp = tmpfile();
    Repo *repo = repo_create(pool, "debian");
    Solvable *solvable;

    failed |= check(fp != 0, "could not create Debian loader input");
    if (fp)
      {
        failed |= check(fwrite(packages, 1, sizeof(packages) - 1, fp) == sizeof(packages) - 1,
                        "could not write Debian loader input");
        rewind(fp);
        failed |= check(repo_add_debpackages(repo, fp, 0) == 0, "Debian repository loader failed");
        fclose(fp);
      }
    failed |= check(repo->nsolvables == 1, "Debian repository loader did not create one solvable");
    if (repo->nsolvables == 1)
      {
        solvable = pool_id2solvable(pool, repo->start);
        failed |= check(!strcmp(pool_id2str(pool, solvable->name), "hello"), "Debian package name was not parsed");
        failed |= check(!strcmp(pool_id2str(pool, solvable->evr), "1:2.0~rc1-1"), "Debian package version was not parsed");
        failed |= check(!strcmp(pool_id2str(pool, solvable->arch), "amd64"), "Debian package architecture was not parsed");
        failed |= check(solvable->requires != 0, "Debian package dependency was not parsed");
        if (solvable->requires)
          failed |= check(!strcmp(pool_dep2str(pool, repo->idarraydata[solvable->requires]), "libc6 >> 2.34"),
                          "Debian strict-greater dependency semantics were not preserved");
      }
  }
#endif
#else
#ifdef LIBSOLVEXT_FEATURE_DEBIAN
  failed |= check(0, "default solvversion.h unexpectedly declares Debian repository support");
#endif
#endif

  pool_free(pool);
  return failed != 0;
}
