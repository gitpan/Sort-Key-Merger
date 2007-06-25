/* -*- Mode: C -*- */

#define PERL_NO_GET_CONTEXT 1

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define KEY0 3

static int
sv_icmp(pTHX_ SV *a, SV *b) {
    IV iv1 = SvIV(a);
    IV iv2 = SvIV(b);
    return iv1 < iv2 ? -1 : iv1 > iv2 ? 1 : 0;
}

static int
sv_ucmp(pTHX_ SV *a, SV *b) {
    UV uv1 = SvUV(a);
    UV uv2 = SvUV(b);
    return uv1 < uv2 ? -1 : uv1 > uv2 ? 1 : 0;
}

static int
sv_ncmp(pTHX_ SV *a, SV *b) {
    NV nv1 = SvNV(a);
    NV nv2 = SvNV(b);
    return nv1 < nv2 ? -1 : nv1 > nv2 ? 1 : 0;
}



/* WARNING: _resort(type, src) does NOT check if its arguments are
 * properly structured, neither it does support magic on them!,
 * calling module has to ensure that these conditions are meet */



MODULE = Sort::Key::Merger		PACKAGE = Sort::Key::Merger		
PROTOTYPES: DISABLE

void
_resort(SV *type, AV *src)
PREINIT:
    I32 (*cmp)(pTHX_ SV *, SV *);
    int min, max, pivot;
    SV **srci, **key0, **keypivot;
    SV *src0;
    STRLEN type_len;
    unsigned char *type_pv;
PPCODE:
    type_pv = SvPV(type, type_len);
    max = av_len(src);
    /* printf("max: %d\n", max); fflush(stdout); */
    if (max > 0) {
	min = 0;
	srci = AvARRAY(src);
	src0 = srci[0];
	key0 = AvARRAY((AV*)(SvRV(src0))) + KEY0;

        for (pivot = 1; min < max; pivot = (max + min + 1) / 2) {
            int k;
	    SV **keypivot = AvARRAY((AV*)(SvRV(srci[pivot]))) + KEY0;

            /* fprintf(stderr, "min: %d, max: %d\n", min, max); fflush(stderr); */
            
            for (k = 0; ; k++) {
                int cmp;

                if (k > type_len)
                    Perl_croak(aTHX_ "internal error: sorting order is ambiguous");
                
                switch (type_pv[k]) {
                case 0:
                    cmp = sv_cmp(key0[k], keypivot[k]);
                    break;
                case 1:
                    cmp = sv_cmp_locale(key0[k], keypivot[k]);
                    break;
                case 2:
                    cmp = sv_ncmp(aTHX_ key0[k], keypivot[k]);
                    break;
                case 3:
                    cmp = sv_icmp(aTHX_ key0[k], keypivot[k]);
                    break;
                case 4:
                    cmp = sv_ucmp(aTHX_ key0[k], keypivot[k]);
                    break;
                case 128:
                    cmp = sv_cmp(keypivot[k], key0[k]);
                    break;
                case 129:
                    cmp = sv_cmp_locale(keypivot[k], key0[k]);
                    break;
                case 130:
                    cmp = sv_ncmp(aTHX_ keypivot[k], key0[k]);
                    break;
                case 131:
                    cmp = sv_icmp(aTHX_ keypivot[k], key0[k]);
                    break;
                case 132:
                    cmp = sv_ucmp(aTHX_ keypivot[k], key0[k]);
                    break;
                default:
                    Perl_croak(aTHX_ "bad key type %d", type_pv[k]);
                }

                if (cmp < 0) {
                    max = pivot - 1;
                    break;
                }
                if (cmp > 0) {
                    min = pivot;
                    break;
                }
	    }
        }
	if (min > 0) {
	    int i;
	    for (i = 0; i < min; i++) {
		srci[i] = srci[i + 1];
	    }
	    srci[min] = src0;
	}
    }
    XSRETURN(0);

