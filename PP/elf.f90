   !
! Copyright (C) 2001-2005 PWSCF group
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
!-----------------------------------------------------------------------
SUBROUTINE do_elf (elf)
  !-----------------------------------------------------------------------
  !
  !  calculatation of the electron localization function
  !
  !  elf = 1/(1+d**2)
  !
  !          where
  !
  !  d = ( t(r) - t_von_Weizacker(r) ) / t_Thomas-Fermi(r)
  !
  !          and
  !
  !  t (r) = (hbar**2/2m) * \sum_{k,i} |grad psi_{k,i}|**2
  !
  !  t_von_Weizaecker(r) = (hbar**2/2m) * 0.25 * |grad rho(r)|**2/rho
  !  t_von_Weizaecker(r) == t_noninteracting-boson
  !
  !  t_Thomas-Fermi (r) = (hbar**2/2m) * 3/5 * (3*pi**2)**(2/3) * rho**(5/3)
  !
  !
  USE kinds, ONLY: DP
  USE constants, ONLY: pi
  USE cell_base, ONLY: omega, tpiba, tpiba2
  USE gvect, ONLY: nr1,nr2,nr3, nrx1,nrx2,nrx3, nrxx, gcutm, ecutwfc, &
       dual, g, ngm, nl, nlm
  USE gsmooth, ONLY : nls, nlsm, nr1s, nr2s, nr3s, ngms, &
                      nrx1s, nrx2s, nrx3s, nrxxs, doublegrid
  USE io_files, ONLY: iunwfc, nwordwfc
  USE klist, ONLY: nks, xk
  USE lsda_mod, ONLY: nspin
  USE scf, ONLY: rho
  USE symme, ONLY: sym_rho, sym_rho_init
  USE wvfct, ONLY: npw, igk, g2kin, nbnd, wg
  USE control_flags, ONLY: gamma_only
  USE wavefunctions_module,  ONLY: evc
  USE mp_global,            ONLY: inter_pool_comm, intra_pool_comm
  USE mp,                   ONLY: mp_sum
  !
  ! I/O variables
  !
  IMPLICIT NONE
  real(DP) :: elf (nrxx)
  !
  ! local variables
  !
  INTEGER :: i, j, k, ibnd, ik, is
  real(DP) :: gv(3), w1, d, fac
  real(DP), ALLOCATABLE :: kkin (:), tbos (:)
  COMPLEX(DP), ALLOCATABLE :: aux (:), aux2 (:)
  !
  CALL infomsg ('do_elf', 'elf + US not fully implemented')
  !
  ALLOCATE (kkin( nrxx))
  ALLOCATE (aux ( nrxxs))
  aux(:) = (0.d0,0.d0)
  kkin(:) = 0.d0
  !
  ! Calculates local kinetic energy, stored in kkin
  !
  DO ik = 1, nks
     !
     !    prepare the indices of this k point
     !
     CALL gk_sort (xk (1, ik), ngm, g, ecutwfc / tpiba2, npw, igk, g2kin)
     !
     !   reads the eigenfunctions
     !
     CALL davcio (evc, nwordwfc, iunwfc, ik, - 1)
     !
     DO ibnd = 1, nbnd
        DO j = 1, 3
           aux(:) = (0.d0,0.d0)
           w1 = wg (ibnd, ik) / omega
           DO i = 1, npw
              gv (j) = (xk (j, ik) + g (j, igk (i) ) ) * tpiba
              aux (nls(igk (i) ) ) = cmplx(0d0, gv (j) ,kind=DP) * evc (i, ibnd)
              IF (gamma_only) THEN
                 aux (nlsm(igk (i) ) ) = cmplx(0d0, -gv (j) ,kind=DP) * &
                      conjg ( evc (i, ibnd) )
              ENDIF
           ENDDO
           CALL cft3s (aux, nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, 2)
           DO i = 1, nrxxs
              kkin(i) = kkin(i) + w1 * (dble(aux(i))**2 + aimag(aux(i))**2)
           ENDDO
           ! j
        ENDDO
        ! ibnd
     ENDDO
     ! ik
  ENDDO
#ifdef __PARA
  !
  ! reduce local kinetic energy across pools
  !
  CALL mp_sum( kkin, inter_pool_comm )
#endif
  !
  ! interpolate the local kinetic energy to the dense grid
  ! Note that for US PP this term is incomplete: it contains
  ! only the contribution from the smooth part of the wavefunction
  !
  IF (doublegrid) THEN
     DEALLOCATE (aux)
     ALLOCATE(aux(nrxx))
     CALL interpolate (kkin, kkin, 1)
  ENDIF
  !
  ! symmetrize the local kinetic energy if needed
  !
  IF ( .not. gamma_only) THEN
     !
     CALL sym_rho_init ( gamma_only )
     !
     aux(:) =  cmplx ( kkin (:), 0.0_dp, kind=dp)
     CALL cft3s (aux, nr1s, nr2s, nr3s, nrx1s, nrx2s, nrx3s, -1)
     ALLOCATE (aux2(ngm))
     aux2(:) = aux(nl(:))
     !
     ! aux2 contains the local kinetic energy in G-space to be symmetrized
     !
     CALL sym_rho ( 1, aux2 )
     !
     aux(:) = (0.0_dp, 0.0_dp)
     aux(nl(:)) = aux2(:)
     DEALLOCATE (aux2)
     CALL cft3 (aux, nr1, nr2, nr3, nrx1, nrx2, nrx3, 1)
     kkin (:) = dble(aux(:))
     !
  ENDIF
  !
  ! Calculate the bosonic kinetic density, stored in tbos
  !          aux --> charge density in Fourier space
  !         aux2 --> iG * rho(G)
  !
  ALLOCATE ( tbos(nrxx), aux2(nrxx) )
  tbos(:) = 0.d0
  !
  ! put the total (up+down) charge density in rho%of_r(*,1)
  !
  DO is = 2, nspin
     rho%of_r (:, 1) =  rho%of_r (:, 1) + rho%of_r (:, is)
  ENDDO
  !
  aux(:) = cmplx( rho%of_r(:, 1), 0.d0 ,kind=DP)
  CALL cft3 (aux, nr1, nr2, nr3, nrx1, nrx2, nrx3, - 1)
  !
  DO j = 1, 3
     aux2(:) = (0.d0,0.d0)
     DO i = 1, ngm
        aux2(nl(i)) = aux(nl(i)) * cmplx(0.0d0, g(j,i)*tpiba,kind=DP)
     ENDDO
     IF (gamma_only) THEN
        DO i = 1, ngm
           aux2(nlm(i)) = aux(nlm(i)) * cmplx(0.0d0,-g(j,i)*tpiba,kind=DP)
        ENDDO
     ENDIF

     CALL cft3 (aux2, nr1, nr2, nr3, nrx1, nrx2, nrx3, 1)
     DO i = 1, nrxx
        tbos (i) = tbos (i) + dble(aux2(i))**2
     ENDDO
  ENDDO
  !
  ! Calculates ELF
  !
  fac = 5.d0 / (3.d0 * (3.d0 * pi**2) ** (2.d0 / 3.d0) )
  elf(:) = 0.d0
  DO i = 1, nrxx
     IF (rho%of_r (i,1) > 1.d-30) THEN
        d = fac / rho%of_r(i,1)**(5d0/3d0) * (kkin(i)-0.25d0*tbos(i)/rho%of_r(i,1))
        elf (i) = 1.0d0 / (1.0d0 + d**2)
     ENDIF
  ENDDO
  DEALLOCATE (aux, aux2, tbos, kkin)
  RETURN
END SUBROUTINE do_elf
