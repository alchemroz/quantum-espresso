!
! Copyright (C) 2002-2005 FPMD-CPV groups
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
#include "f_defs.h"


MODULE kohn_sham_states


   USE io_files, ONLY: ksunit, ks_file, ks_emp_file

   IMPLICIT NONE
   SAVE

   PRIVATE

   ! ...   print KS states to file KS.indx_ksout if ksout true
   LOGICAL :: tksout                        
   LOGICAL :: tksout_emp 

   INTEGER, ALLOCATABLE :: indx_ksout(:,:)  ! (state inds, spin indxs)
   INTEGER, ALLOCATABLE :: n_ksout(:)       ! (spin indxs)
   INTEGER, ALLOCATABLE :: indx_ksout_emp(:,:)  ! (state inds, spin indxs)
   INTEGER, ALLOCATABLE :: n_ksout_emp(:)       ! (spin indxs)

   PUBLIC :: ks_states_init, kohn_sham, ks_states_closeup
   PUBLIC :: n_ksout, indx_ksout, ks_states, tksout
   PUBLIC :: ks_states_force_pairing

!  ----------------------------------------------
CONTAINS
!  ----------------------------------------------


   SUBROUTINE ks_states_init( nspin, nprnks, iprnks, nprnks_emp, iprnks_emp )

      INTEGER, INTENT(IN) :: nspin, nprnks(:), nprnks_emp(:)
      INTEGER, INTENT(IN) :: iprnks(:,:)
      INTEGER, INTENT(IN) :: iprnks_emp(:,:)

      INTEGER :: i, ip, k, nstates

      ! ...   Tell the code which Kohn-Sham state should be printed to file
      !
      IF( ALLOCATED( n_ksout    ) ) DEALLOCATE( n_ksout )
      IF( ALLOCATED( indx_ksout ) ) DEALLOCATE( indx_ksout )
      !
      tksout = ANY( nprnks > 0 )
      !
      IF( tksout ) THEN
         nstates = MAXVAL( nprnks )
         ALLOCATE( n_ksout( nspin ) )
         ALLOCATE( indx_ksout( nstates, nspin) )
         n_ksout( 1:nspin ) = nprnks( 1:nspin )
         DO i = 1, nspin
           DO k = 1, nprnks( i )
              indx_ksout( k, i ) = iprnks( k, i )
           END DO
         END DO
      END IF

      IF( ALLOCATED( n_ksout_emp    ) ) DEALLOCATE( n_ksout_emp )
      IF( ALLOCATED( indx_ksout_emp ) ) DEALLOCATE( indx_ksout_emp )
      !
      tksout_emp = ANY( nprnks_emp > 0 )
      !
      IF( tksout_emp ) THEN
         nstates = MAXVAL( nprnks_emp )
         ALLOCATE( n_ksout_emp( nspin ) )
         ALLOCATE( indx_ksout_emp( nstates, nspin ) )
         n_ksout_emp( 1:nspin ) = nprnks_emp( 1:nspin )
         DO i = 1, nspin
            DO k = 1, n_ksout_emp( i )
               indx_ksout_emp( k, i ) = iprnks_emp( k, i )
            END DO
         END DO
      END IF

      RETURN
   END SUBROUTINE ks_states_init

!  ----------------------------------------------

   SUBROUTINE ks_states_closeup()
      IF( ALLOCATED( indx_ksout ) ) DEALLOCATE( indx_ksout )
      IF( ALLOCATED( n_ksout ) ) DEALLOCATE( n_ksout )
      tksout = .FALSE.
      IF( ALLOCATED( indx_ksout_emp ) ) DEALLOCATE( indx_ksout_emp )
      IF( ALLOCATED( n_ksout_emp ) ) DEALLOCATE( n_ksout_emp )
      tksout_emp = .FALSE.
      RETURN
   END SUBROUTINE ks_states_closeup

!  ----------------------------------------------

   SUBROUTINE kohn_sham(ispin, c, cdesc, eforces )

        ! ...   declare modules
        USE kinds
        USE wave_functions,   ONLY: crot
        USE wave_constrains,  ONLY: update_lambda
        USE wave_types,       ONLY: wave_descriptor
        USE electrons_module, ONLY: nb_l
        USE electrons_base,   ONLY: nupdwn

        IMPLICIT NONE

        ! ...   declare subroutine arguments
        COMPLEX(DP), INTENT(INOUT) ::  c(:,:)
        TYPE (wave_descriptor), INTENT(IN) :: cdesc
        INTEGER, INTENT(IN) :: ispin
        COMPLEX(DP) :: eforces(:,:)

        ! ...   declare other variables
        INTEGER ::  ib, nb_g, nrl
        REAL(DP),    ALLOCATABLE :: gam(:,:)
        REAL(DP),    ALLOCATABLE :: eig(:)
        LOGICAL :: tortho = .TRUE.

        ! ...   end of declarations

        nb_g = nupdwn( ispin )

        IF( nb_g < 1 ) THEN
            
           eforces = 0.0d0

        ELSE

           nrl = nb_l( ispin )

           ALLOCATE( eig( nb_g ) )
           ALLOCATE( gam( nrl, nb_g ) )

           DO ib = 1, nb_g
              CALL update_lambda( ib, gam, c(:,:), cdesc, eforces(:,ib) )
           END DO
           CALL crot( ispin, c(:,:), cdesc, gam, eig )

           DEALLOCATE( gam, eig )

        END IF

        RETURN
        ! ...
   END SUBROUTINE kohn_sham

!  ----------------------------------------------

      SUBROUTINE ks_states(cf, wfill, ce, wempt, occ, vpot, eigr, bec )

        ! ...   declare modules
        USE kinds
        USE mp_global, ONLY: intra_image_comm
        USE io_global, ONLY: ionode
        USE io_global, ONLY: stdout
        USE wave_types, ONLY: wave_descriptor
        USE forces
        USE brillouin, ONLY: kpoints, kp
        USE pseudo_projector, ONLY: projector
        USE control_flags, ONLY: timing, force_pairing

        IMPLICIT NONE

        ! ...   declare subroutine arguments
        COMPLEX(DP), INTENT(INOUT) :: cf(:,:,:,:), ce(:,:,:,:)
        TYPE (wave_descriptor), INTENT(IN) :: wfill, wempt
        COMPLEX(DP)  ::  eigr(:,:)
        REAL(DP), INTENT(IN)  ::  occ(:,:,:), bec(:,:)
        REAL (DP) ::  vpot(:,:)

        ! ...   declare other variables
        INTEGER ::  i, ik, ib, nk, ig, ngw, nb_g, nb_l, ispin, nspin, iks
        INTEGER ::  ispin_wfc
        LOGICAL  :: tortho = .TRUE.
        CHARACTER(LEN=4) :: nom
        CHARACTER(LEN=256) :: file_name
        CHARACTER(LEN=10), DIMENSION(2) :: spin_name
        REAL(DP) :: s0, s1, s2, s3

        COMPLEX(DP), ALLOCATABLE :: eforce(:,:)
        REAL(DP), ALLOCATABLE :: fi(:,:)

        REAL(DP), EXTERNAL :: cclock
        CHARACTER (LEN=6), EXTERNAL :: int_to_char


        ! ...   end of declarations

        nk    = wfill%nkl
        nspin = wfill%nspin

        IF( .NOT. wfill%gamma ) &
          CALL errore( ' ks_states ', ' only gamma is implemented ', 1 )

        IF( timing ) s0 = cclock()

        DO ispin = 1, nspin

          ngw  = wfill%ngwl
          nb_l = wfill%nbl( ispin )

          ispin_wfc = ispin
          IF( force_pairing ) ispin_wfc = 1

          IF( nb_l > 0 ) THEN

            ALLOCATE(  eforce( ngw,  nb_l ) )

            CALL dforce_all( ispin, cf(:,:,1,ispin_wfc), wfill, occ(:,1,ispin), eforce, &
              vpot(:,ispin), eigr, bec )

            CALL kohn_sham( ispin, cf(:,:,1,ispin_wfc), wfill, eforce )

            DEALLOCATE( eforce )

          END IF

          IF( tksout_emp ) THEN

            ngw  = wempt%ngwl
            nb_l = wempt%nbl( ispin )

            IF( nb_l > 0 ) THEN

              ALLOCATE( fi( nb_l, nk ) )
              DO ik = 1, nk
                fi( 1:nb_l, ik ) = 2.0d0 / nspin
              END DO

              ALLOCATE(  eforce( ngw,  nb_l ) )

              CALL dforce_all( ispin, ce(:,:,1,ispin), wempt, fi(:,1), eforce, &
                               vpot(:,ispin), eigr, bec )

              CALL kohn_sham( ispin, ce(:,:,1,ispin), wempt, eforce )

              DEALLOCATE( eforce )
              DEALLOCATE( fi )

            END IF

          END IF

        END DO

        IF( timing ) s1 = cclock()

        IF( tksout .OR. tksout_emp ) THEN
          CALL print_all_states(cf, wfill, ce, wempt )
        END IF

        IF( timing ) THEN
          s2 = cclock()
          IF( ionode ) THEN
            WRITE( stdout,fmt="(3X,'time for KS ortho     = ',F8.2)") (s1-s0)
            WRITE( stdout,fmt="(3X,'time for KS print out = ',F8.2)") (s2-s1)
          END IF
        END IF
        ! ...
        RETURN
        ! ...
      END SUBROUTINE ks_states

!  ----------------------------------------------

      SUBROUTINE print_all_states(cf, wfill, ce, wempt )

        ! ...   declare modules
        USE kinds
        USE mp_global, ONLY: intra_image_comm
        USE io_global, ONLY: ionode
        USE io_global, ONLY: stdout
        USE wave_types, ONLY: wave_descriptor
        USE forces
        USE brillouin, ONLY: kpoints, kp
        USE pseudo_projector, ONLY: projector
        USE control_flags, ONLY: timing, force_pairing

        IMPLICIT NONE

        ! ...   declare subroutine arguments
        COMPLEX(DP), INTENT(INOUT) :: cf(:,:,:,:), ce(:,:,:,:)
        TYPE (wave_descriptor), INTENT(IN) :: wfill, wempt

        ! ...   declare other variables
        INTEGER ::  i, ispin, iks, ispin_wfc

        CHARACTER(LEN=256) :: file_name
        CHARACTER(LEN=10), DIMENSION(2) :: spin_name
        CHARACTER (LEN=6), EXTERNAL :: int_to_char

        IF( tksout .OR. tksout_emp ) THEN

          IF (ionode) THEN
            WRITE( stdout,*) 
            WRITE( stdout,'( "   Khon Sham state")') 
            WRITE( stdout,'( "   ---------------")') 
          END IF

          IF( wfill%nspin == 2 ) THEN
            spin_name(1) = '_UP_'
            spin_name(2) = '_DW_'
          ELSE
            spin_name(1) = '_'
            spin_name(2) = '_'
          END IF

          DO ispin = 1, wfill%nspin
            ispin_wfc = ispin
            IF( force_pairing ) ispin_wfc = 1
            IF( tksout ) THEN
              DO i = 1, n_ksout(ispin)
                iks = indx_ksout(i, ispin)
                IF( ( iks > 0 ) .AND. ( iks <= wfill%nbt( ispin ) ) ) THEN
                  file_name = TRIM( ks_file ) // &
                            & trim(spin_name(ispin)) // trim( int_to_char( iks ) )
                  CALL print_ks_states( cf(:,iks,1,ispin_wfc), file_name )
                END IF
              END DO
            END IF
            IF( tksout_emp ) THEN
              DO i = 1, n_ksout_emp(ispin)
                iks = indx_ksout_emp(i, ispin)
                IF( ( iks > 0 ) .AND. ( iks <= wempt%nbt( ispin ) ) ) THEN
                  file_name = TRIM( ks_emp_file ) // &
                            & trim(spin_name(ispin)) // trim( int_to_char( iks ) )
                  CALL print_ks_states( ce(:,iks,1,ispin), file_name )
                END IF
              END DO
            END IF
          END DO

        END IF

        RETURN
        ! ...
      END SUBROUTINE print_all_states


!  ----------------------------------------------


      SUBROUTINE ks_states_force_pairing(cf, wfill, ce, wempt, occ, vpot, eigr, bec )

        ! ...   declare modules
        USE kinds
        USE mp_global, ONLY: intra_image_comm
        USE io_global, ONLY: ionode
        USE io_global, ONLY: stdout
        USE wave_types, ONLY: wave_descriptor
        USE forces
        USE brillouin, ONLY: kpoints, kp
        USE pseudo_projector, ONLY: projector
        USE control_flags, ONLY: timing
        USE electrons_module, ONLY: nupdwn, nspin

        IMPLICIT NONE

        ! ...   declare subroutine arguments
        COMPLEX(DP), INTENT(INOUT) :: cf(:,:,:,:), ce(:,:,:,:)
        TYPE (wave_descriptor), INTENT(IN) :: wfill, wempt
        COMPLEX(DP)  ::  eigr(:,:)
        REAL(DP), INTENT(IN)  ::  occ(:,:,:), bec(:,:)
        REAL (DP) ::  vpot(:,:)

        ! ...   declare other variables
        INTEGER ::  i, ik, ib, nk, ig, ngw, nb_g, nb_l, iks, nb, ispin
        LOGICAL  :: tortho = .TRUE.
        CHARACTER(LEN=4) :: nom
        CHARACTER(LEN=256) :: file_name
        CHARACTER(LEN=10), DIMENSION(2) :: spin_name
        REAL(DP) :: s0, s1, s2, s3

        COMPLEX(DP), ALLOCATABLE :: eforce(:,:,:)
        REAL(DP), ALLOCATABLE :: fi(:,:)

        CHARACTER (LEN=6), EXTERNAL :: int_to_char
        REAL(DP), EXTERNAL :: cclock


        ! ...   end of declarations
        !  ----------------------------------------------

        nk    = wfill%nkl

        IF( .NOT. wfill%gamma ) &
          CALL errore( ' ks_states_force_pairing ', ' only gamma is implemented ', 1 )

        IF( nspin == 1 ) &
          CALL errore(' ks_states_forced_pairing ',' inconsistent nspin ', 1)

        IF( nupdwn(1) < nupdwn(2) ) &
          CALL errore(' ks_states_forced_pairing ',' inconsistent nupdwn ', 1)

        IF( timing ) s0 = cclock()

        ngw  = wfill%ngwl
        nb   = nupdwn(1)

        IF( nb > 0 ) THEN

          ALLOCATE(  eforce( ngw, nb, 2 ) )

          CALL dforce_all( 1, cf(:,:,1,1), wfill, occ(:,1,1), eforce(:,:,1), &
              vpot(:,1), eigr, bec )
          CALL dforce_all( 2, cf(:,:,1,1), wfill, occ(:,1,2), eforce(:,:,2), &
              vpot(:,2), eigr, bec )

          DO i = 1, nupdwn(2)
            eforce(:,i,1) = occ(i,1,1) * eforce(:,i,1) + occ(i,1,2) * eforce(:,i,2)
          END DO
          DO i = nupdwn(2)+1, nupdwn(1)
            eforce(:,i,1) = occ(i,1,1) * eforce(:,i,1)
          END DO

          CALL kohn_sham( 1, cf(:,:,1,1), wfill, eforce(:,:,1) )

          DEALLOCATE( eforce )

        END IF

        IF( tksout_emp ) THEN

          ngw  = wempt%ngwl
          nb_l = wempt%nbl( 1 )

          IF( nb_l > 0 ) THEN

            ALLOCATE( fi( nb_l, nk ) )
            DO ik = 1, nk
              fi( 1:nb_l, ik ) = 2.0d0
            END DO

            ALLOCATE(  eforce( ngw,  nb_l, 1 ))

            CALL dforce_all( 1, ce(:,:,1,1), wempt, fi(:,1), eforce(:,:,1), vpot(:,1), &
                             eigr, bec )

            CALL kohn_sham( 1, ce(:,:,1,1), wempt, eforce(:,:,1) )

            CALL dforce_all( 2, ce(:,:,1,2), wempt, fi(:,1), eforce(:,:,1), vpot(:,2), &
                             eigr, bec )

            CALL kohn_sham( 2, ce(:,:,1,2), wempt, eforce(:,:,1) )

            DEALLOCATE( eforce )
            DEALLOCATE( fi )

          END IF

        END IF

        IF( timing ) s1 = cclock()

        IF( tksout .OR. tksout_emp ) THEN
          CALL print_all_states(cf, wfill, ce, wempt )
        END IF

        IF( timing ) THEN
          s2 = cclock()
          IF( ionode ) THEN
            WRITE( stdout,fmt="(3X,'time for KS ortho     = ',F8.2)") (s1-s0)
            WRITE( stdout,fmt="(3X,'time for KS print out = ',F8.2)") (s2-s1)
          END IF
        END IF
        !
        RETURN
        !
      END SUBROUTINE ks_states_force_pairing


!  ----------------------------------------------

      SUBROUTINE print_ks_states( c, file_name )

        USE kinds
        USE mp_global, ONLY: intra_image_comm
        USE mp, ONLY: mp_sum
        USE io_global, ONLY: ionode, ionode_id
        USE io_global, ONLY: stdout
        USE gvecw, ONLY: ngw
        USE fft_base, ONLY: dfftp, dffts
        USE grid_dimensions, ONLY: nr1, nr2, nr3, nr1x, nr2x, nr3x, nnrx
        USE fft_module, ONLY: invfft
        USE xml_io_base, ONLY: write_rho_xml
        USE mp_global,       ONLY: nproc_image, me_image

        IMPLICIT NONE

        COMPLEX(DP),      INTENT(IN) :: c(:)
        CHARACTER(LEN=*), INTENT(IN) :: file_name
        REAL(DP),    ALLOCATABLE :: rpsi2(:)
        COMPLEX(DP), ALLOCATABLE :: psi(:)
        INTEGER   ::  i
        REAL(DP) :: charge

        ALLOCATE( psi( nnrx ) )
        ALLOCATE( rpsi2( nnrx ) )

        CALL c2psi( psi, dffts%nnr, c, c, ngw, 1 )
        CALL invfft( 'Wave', psi, dffts%nr1, dffts%nr2, dffts%nr3, dffts%nr1x, dffts%nr2x, dffts%nr3x )

        DO i = 1, nnrx
           rpsi2( i ) = DBLE( psi( i ) )**2
        END DO
        charge = SUM( rpsi2 )

        CALL write_rho_xml( file_name, rpsi2, nr1, nr2, nr3, nr1x, nr2x, dfftp%ipp, dfftp%npp )
        
        CALL mp_sum( charge, intra_image_comm )

        IF ( ionode ) THEN
          WRITE( stdout,'(3X,A15," integrated charge : ",F14.5)')  &
     &      TRIM(file_name), charge / DBLE(nr1*nr2*nr3)
        END IF

        DEALLOCATE( rpsi2, psi )
        ! ...
        RETURN
        ! ...
      END SUBROUTINE print_ks_states

!  ----------------------------------------------
!
END MODULE kohn_sham_states
