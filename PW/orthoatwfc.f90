!
! Copyright (C) 2001 PWSCF group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
#include "f_defs.h"
!
!-----------------------------------------------------------------------
SUBROUTINE orthoatwfc
  !-----------------------------------------------------------------------
  !
  ! This routine is meant to orthogonalize all the atomic wfcs. This is
  ! useful when we want to compute the occupation of the atomic orbitals
  ! in order to make lda+U calculations
  !
  USE kinds,      ONLY : DP
  USE parameters, ONLY : nchix
  USE io_global,  ONLY : stdout
  USE io_files,   ONLY : iunat, nwordatwfc, iunigk
  USE ions_base,  ONLY : nat
  USE basis,      ONLY : natomwfc
  USE klist,      ONLY : nks, xk
  USE ldaU,       ONLY : swfcatom, swfcatom_nc, U_projection
  USE wvfct,      ONLY : npwx, npw, igk, gamma_only
  USE uspp,       ONLY : nkb, vkb
  USE becmod,     ONLY : becp, rbecp, becp_nc
  USE noncollin_module, ONLY : noncolin, npol
  ! 
  IMPLICIT NONE
  !
  !
  INTEGER :: ik, ibnd, info, i, j, k, na, nb, nt, isym, n, ntemp, m, &
       l, lm, ltot, ntot, ipol
  ! the k point under consideration
  ! counter on bands
  INTEGER :: nchi_, lchi_ (nchix)
  LOGICAL :: exst
  REAL(DP) :: t0, scnds
  ! cpu time spent
  LOGICAL :: orthogonalize_wfc
     
  COMPLEX(DP) :: temp, t (5)
  COMPLEX(DP) , ALLOCATABLE :: wfcatom (:,:), work (:,:), overlap (:,:)
  COMPLEX(DP), ALLOCATABLE :: wfcatom_nc(:,:,:)
  REAL(DP) , ALLOCATABLE :: e (:)

  t0 = scnds ()
  
  IF (noncolin) THEN
     ALLOCATE (wfcatom_nc( npwx, npol, natomwfc))    
     wfcatom_nc=(0.D0,0.D0)
  ELSE
     ALLOCATE (wfcatom( npwx, natomwfc))    
  END IF
  ALLOCATE (overlap( natomwfc , natomwfc))    
  ALLOCATE (work   ( natomwfc , natomwfc))    
  ALLOCATE (e      ( natomwfc))    

  IF (U_projection=="file") THEN
     WRITE( stdout,*) 'LDA+U Projector read from file '
     RETURN
  END IF

  IF (U_projection=="atomic") THEN
     orthogonalize_wfc = .FALSE.
     WRITE( stdout,*) 'Atomic wfc used for LDA+U Projector are NOT orthogonalized'
  ELSE IF (U_projection=="ortho-atomic") THEN
     orthogonalize_wfc = .TRUE.
     WRITE( stdout,*) 'Atomic wfc used for LDA+U Projector are orthogonalized'
     IF (gamma_only) THEN
        WRITE( stdout,*) 'Gamma-only calculation for this case not implemented'
        STOP
     END IF
  ELSE
     WRITE( stdout,*) "U_projection_type =", U_projection
     CALL errore ("orthoatwfc"," this U_projection_type is not valid",1)
  END IF

  ! Allocate the array becp = <beta|wfcatom>
  IF ( gamma_only ) THEN 
     ALLOCATE (rbecp (nkb,natomwfc)) 
  ELSE
     IF (noncolin) THEN
        ALLOCATE ( becp_nc (nkb, npol, natomwfc)) 
     ELSE
        ALLOCATE ( becp (nkb,natomwfc)) 
     END IF
  END IF
  
  IF (nks > 1) REWIND (iunigk)
  
  DO ik = 1, nks
     
     IF (nks > 1) READ (iunigk) npw, igk
     
     overlap(:,:) = (0.d0,0.d0)
     work(:,:) = (0.d0,0.d0)
     
     IF (noncolin) THEN
        CALL atomic_wfc_nc (ik, wfcatom_nc)
     ELSE
        CALL atomic_wfc (ik, wfcatom)
     END IF
     CALL init_us_2 (npw, igk, xk (1, ik), vkb)
     
     IF ( gamma_only ) THEN 
        CALL pw_gemm ('Y', nkb, natomwfc, npw, vkb, npwx, &
             wfcatom, npwx, rbecp, nkb) 
     ELSE
        IF (noncolin) THEN
           CALL ccalbec_nc(nkb,npwx,npw,npol,natomwfc,becp_nc,vkb,wfcatom_nc)
        ELSE
           CALL ccalbec (nkb, npwx, npw, natomwfc, becp, vkb, wfcatom)
        END IF
     ENDIF

     IF (noncolin) THEN
        CALL s_psi_nc (npwx, npw, natomwfc, wfcatom_nc, swfcatom_nc)
     ELSE
        CALL s_psi (npwx, npw, natomwfc, wfcatom, swfcatom)
     ENDIF

     !
     ! calculate overlap matrix
     !
     IF (noncolin) THEN
        CALL ZGEMM ('c', 'n', natomwfc, natomwfc, npwx*npol, (1.d0, 0.d0), &
         wfcatom_nc,npwx,swfcatom_nc,npwx,(0.d0,0.d0),overlap,natomwfc)
     ELSE
         CALL ZGEMM ('c', 'n', natomwfc, natomwfc, npw, (1.d0, 0.d0) , &
             wfcatom, npwx, swfcatom, npwx, (0.d0, 0.d0) , overlap, natomwfc)
     END IF
#ifdef __PARA
     CALL reduce (2 * natomwfc * natomwfc, overlap)
#endif
     IF (.not.orthogonalize_wfc) THEN
        DO i = 1, natomwfc
           DO j = i+1, natomwfc
              overlap(i,j) = cmplx(0.d0,0.d0)
              overlap(j,i) = cmplx(0.d0,0.d0)
           ENDDO
        ENDDO
     END IF
     !
     ! find O^-.5
     !
     CALL cdiagh (natomwfc, overlap, natomwfc, e, work)
     DO i = 1, natomwfc
        e (i) = 1.d0 / dsqrt (e (i) )
     ENDDO
     DO i = 1, natomwfc
        DO j = i, natomwfc
           temp = (0.d0, 0.d0)
           DO k = 1, natomwfc
              temp = temp + e (k) * work (j, k) * CONJG (work (i, k) )
           ENDDO
           overlap (i, j) = temp
           IF (j.NE.i) overlap (j, i) = CONJG (temp)
        ENDDO
     ENDDO
     !
     ! trasform atomic orbitals O^-.5 psi
     !
     DO i = 1, npw
        work(:,1) = (0.d0,0.d0)
        IF (noncolin) THEN
           DO ipol=1,npol
              CALL ZGEMV ('n',natomwfc,natomwfc,(1.d0,0.d0),overlap, &
                   natomwfc,swfcatom_nc(i,ipol,1),npwx*npol, &
                                       (0.d0,0.d0),work,1)
              CALL ZCOPY (natomwfc,work,1,swfcatom_nc(i,ipol,1),npwx*npol)
           END DO
        ELSE
           CALL ZGEMV ('n', natomwfc, natomwfc, (1.d0, 0.d0) , overlap, &
                natomwfc, swfcatom (i, 1) , npwx, (0.d0, 0.d0) , work, 1)
           CALL ZCOPY (natomwfc, work, 1, swfcatom (i, 1), npwx)
        END IF
     ENDDO
        
     IF (noncolin) THEN
        CALL davcio (swfcatom_nc, nwordatwfc, iunat, ik, 1)
     ELSE
        CALL davcio (swfcatom, nwordatwfc, iunat, ik, 1)
     ENDIF
     
  ENDDO
  DEALLOCATE (overlap)
  DEALLOCATE (work)
  DEALLOCATE (e)
  IF (noncolin) THEN
     DEALLOCATE (wfcatom_nc)
  ELSE
     DEALLOCATE (wfcatom)
  END IF
  IF ( gamma_only ) THEN 
     DEALLOCATE (rbecp) 
  ELSE
     IF (noncolin) THEN
        DEALLOCATE (becp_nc) 
     ELSE
        DEALLOCATE (becp) 
     END IF
  END IF
  !
  RETURN
     
END SUBROUTINE orthoatwfc
