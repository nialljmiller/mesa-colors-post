program colors_post_proc

   use const_lib,   only: const_init
   use const_def,   only: dp
   use colors_lib,  only: colors_init, alloc_colors_handle_using_inlist, free_colors_handle, &
                          colors_shutdown, how_many_colors_history_columns, &
                          data_for_colors_history_columns
   use colors_def,  only: Colors_General_Info, get_colors_ptr, &
                          num_color_filters, color_filter_names

   implicit none

   ! --- post_proc controls ---
   character(len=512) :: history_file, output_file, metallicity_col, mesa_dir_in

   ! --- colors handle ---
   integer                            :: handle, ierr, n_cols
   type(Colors_General_Info), pointer :: rq

   ! --- history data ---
   integer  :: n_models
   real(dp), allocatable :: age(:), teff(:), log_g(:), metallicity(:), radius(:)

   ! --- per-model output ---
   character(len=80), allocatable :: col_names(:)
   real(dp),          allocatable :: vals(:)

   integer :: i, out_unit

   ! 1. initialise MESA constants
   call get_environment_variable('MESA_DIR', mesa_dir_in)
   call const_init(trim(mesa_dir_in), ierr)
   if (ierr /= 0) error stop 'const_init failed'

   ! 2. read &post_proc namelist
   call read_post_proc_controls('inlist', history_file, output_file, metallicity_col)

   ! 3. initialise colors module; alloc_colors_handle_using_inlist reads the &colors
   !    namelist and calls colors_setup_tables internally
   call colors_init(.true., '', ierr)
   if (ierr /= 0) error stop 'colors_init failed'

   handle = alloc_colors_handle_using_inlist('inlist', ierr)
   if (ierr /= 0) error stop 'alloc_colors_handle_using_inlist failed'

   call get_colors_ptr(handle, rq, ierr)
   if (ierr /= 0) error stop 'get_colors_ptr failed'

   ! 4. read the history file
   call read_history_file(history_file, metallicity_col, &
                          n_models, age, teff, log_g, metallicity, radius, ierr)
   if (ierr /= 0) error stop 'failed to read history file'
   write(*,'(a,i0,a)') 'read ', n_models, ' models from history file'

   ! 5. open output and write header
   n_cols = how_many_colors_history_columns(handle)
   allocate(col_names(n_cols), vals(n_cols))

   open(newunit=out_unit, file=trim(output_file), status='replace', action='write')
   call write_output_header(out_unit, n_cols, col_names, handle)

   ! 6. main loop
   do i = 1, n_models
      ! data_for_colors_history_columns signature:
      ! (t_eff, log_g, R, metallicity, model_number, colors_handle, n, names, vals, ierr)
      call data_for_colors_history_columns( &
            teff(i), log_g(i), radius(i), metallicity(i), i, &
            handle, n_cols, col_names, vals, ierr)
      if (ierr /= 0) then
         write(*,'(a,i0)') 'warning: colors calculation failed at model ', i
         cycle
      end if
      call write_output_row(out_unit, age(i), teff(i), log_g(i), metallicity(i), n_cols, vals)
   end do

   close(out_unit)
   write(*,'(2a)') 'output written to ', trim(output_file)

   call free_colors_handle(handle)
   call colors_shutdown()

contains

   ! ---------------------------------------------------------------------------
   subroutine read_post_proc_controls(filename, history_file, output_file, metallicity_col)
      character(len=*), intent(in)  :: filename
      character(len=*), intent(out) :: history_file, output_file, metallicity_col

      character(len=512) :: history_file_nml, output_file_nml, metallicity_col_nml
      integer :: io, ios

      namelist /post_proc/ history_file_nml, output_file_nml, metallicity_col_nml

      history_file_nml    = 'LOGS/history.data'
      output_file_nml     = 'post_proc_output.data'
      metallicity_col_nml = 'initial_feh'

      open(newunit=io, file=trim(filename), status='old', action='read', iostat=ios)
      if (ios /= 0) then
         write(*,'(3a)') 'warning: could not open ', trim(filename), ', using &post_proc defaults'
      else
         read(io, nml=post_proc, iostat=ios)
         close(io)
         if (ios /= 0) write(*,*) 'warning: &post_proc namelist not found, using defaults'
      end if

      history_file    = history_file_nml
      output_file     = output_file_nml
      metallicity_col = metallicity_col_nml

   end subroutine read_post_proc_controls

   ! ---------------------------------------------------------------------------
   subroutine read_history_file(filename, metallicity_col, n_models, &
                                 age, teff, log_g, metallicity, radius, ierr)
      character(len=*), intent(in)  :: filename, metallicity_col
      integer, intent(out)          :: n_models, ierr
      real(dp), allocatable, intent(out) :: age(:), teff(:), log_g(:), metallicity(:), radius(:)

      integer :: io, ios, i, n_cols
      character(len=4096) :: line
      character(len=64), allocatable :: headers(:)
      integer  :: idx_age, idx_teff, idx_logg, idx_radius, idx_meta
      logical  :: teff_is_log, radius_is_log, meta_found
      real(dp), allocatable :: row(:)

      ierr = 0
      open(newunit=io, file=trim(filename), status='old', action='read', iostat=ierr)
      if (ierr /= 0) then
         write(*,'(2a)') 'error: cannot open history file ', trim(filename)
         return
      end if

      ! mesa history.data layout: 6 header lines, then data.
      ! lines 1-2: version block, lines 3-4: metadata block,
      ! line 5: column index integers, line 6: column names.
      do i = 1, 5
         read(io, '(A)', iostat=ios) line
         if (ios /= 0) then
            write(*,*) 'error: history file has fewer than 5 header lines'
            ierr = -1; close(io); return
         end if
      end do
      read(io, '(A)', iostat=ios) line
      if (ios /= 0) then
         write(*,*) 'error: failed to read column name line'
         ierr = -1; close(io); return
      end if

      call split_string(trim(adjustl(line)), headers, n_cols)

      idx_age  = find_col(headers, n_cols, 'star_age')
      idx_logg = find_col(headers, n_cols, 'log_g')

      idx_teff    = find_col(headers, n_cols, 'log_Teff')
      teff_is_log = (idx_teff > 0)
      if (idx_teff < 1) idx_teff = find_col(headers, n_cols, 'Teff')

      idx_radius    = find_col(headers, n_cols, 'log_R')
      radius_is_log = (idx_radius > 0)
      if (idx_radius < 1) idx_radius = find_col(headers, n_cols, 'radius')

      idx_meta   = find_col(headers, n_cols, trim(metallicity_col))
      meta_found = (idx_meta > 0)

      if (idx_age    < 1) then; write(*,*) 'error: star_age column not found';       ierr = -1; end if
      if (idx_teff   < 1) then; write(*,*) 'error: log_Teff/Teff column not found';  ierr = -1; end if
      if (idx_logg   < 1) then; write(*,*) 'error: log_g column not found';           ierr = -1; end if
      if (idx_radius < 1) then; write(*,*) 'error: log_R/radius column not found';    ierr = -1; end if
      if (ierr /= 0) then; close(io); return; end if

      if (.not. meta_found) &
         write(*,'(3a)') 'warning: metallicity column "', trim(metallicity_col), &
                         '" not found; defaulting to 0.0'

      ! count data rows
      n_models = 0
      do
         read(io, '(A)', iostat=ios) line
         if (ios /= 0) exit
         if (len_trim(line) == 0) cycle
         n_models = n_models + 1
      end do

      allocate(age(n_models), teff(n_models), log_g(n_models), &
               metallicity(n_models), radius(n_models), row(n_cols))

      rewind(io)
      do i = 1, 6
         read(io, '(A)', iostat=ios) line
      end do

      do i = 1, n_models
         read(io, *, iostat=ios) row(1:n_cols)
         if (ios /= 0) then
            write(*,'(a,i0)') 'error: failed reading data row ', i
            ierr = -1; close(io); return
         end if

         age(i)   = row(idx_age)
         log_g(i) = row(idx_logg)

         if (teff_is_log) then
            teff(i) = 10.0d0**row(idx_teff)
         else
            teff(i) = row(idx_teff)
         end if

         ! log_R is log10 of radius in solar radii; Rsun = 6.957e10 cm
         if (radius_is_log) then
            radius(i) = (10.0d0**row(idx_radius)) * 6.957d10
         else
            radius(i) = row(idx_radius) * 6.957d10
         end if

         if (meta_found) then
            metallicity(i) = row(idx_meta)
         else
            metallicity(i) = 0.0d0
         end if
      end do

      close(io)
      deallocate(row, headers)

   end subroutine read_history_file

   ! ---------------------------------------------------------------------------
   subroutine write_output_header(unit, n_cols, col_names, handle)
      integer, intent(in)           :: unit, n_cols, handle
      character(len=80), intent(out) :: col_names(n_cols)
      real(dp) :: dummy_vals(n_cols)
      integer :: dummy_ierr, j

      ! call once with dummy stellar params just to populate col_names
      call data_for_colors_history_columns( &
            5778.0d0, 4.44d0, 6.957d10, 0.0d0, 1, &
            handle, n_cols, col_names, dummy_vals, dummy_ierr)

      write(unit, '(a)', advance='no') 'star_age  Teff  log_g  metallicity'
      do j = 1, n_cols
         write(unit, '(2a)', advance='no') '  ', trim(col_names(j))
      end do
      write(unit, *)

   end subroutine write_output_header

   ! ---------------------------------------------------------------------------
   subroutine write_output_row(unit, age, teff, log_g, metallicity, n_cols, vals)
      integer, intent(in)  :: unit, n_cols
      real(dp), intent(in) :: age, teff, log_g, metallicity, vals(n_cols)
      integer :: j

      write(unit, '(*(1x,es14.6))', advance='no') age, teff, log_g, metallicity
      do j = 1, n_cols
         write(unit, '(1x,es14.6)', advance='no') vals(j)
      end do
      write(unit, *)

   end subroutine write_output_row

   ! ---------------------------------------------------------------------------
   subroutine split_string(str, tokens, n)
      character(len=*), intent(in) :: str
      character(len=64), allocatable, intent(out) :: tokens(:)
      integer, intent(out) :: n

      integer :: i, start, slen
      logical :: in_token

      slen = len_trim(str)
      n = 0
      in_token = .false.
      do i = 1, slen
         if (str(i:i) /= ' ' .and. .not. in_token) then
            n = n + 1; in_token = .true.
         else if (str(i:i) == ' ') then
            in_token = .false.
         end if
      end do

      allocate(tokens(n))
      n = 0; in_token = .false.; start = 1
      do i = 1, slen
         if (str(i:i) /= ' ' .and. .not. in_token) then
            start = i; in_token = .true.
         else if (str(i:i) == ' ' .and. in_token) then
            n = n + 1; tokens(n) = str(start:i-1); in_token = .false.
         end if
      end do
      if (in_token) then
         n = n + 1; tokens(n) = str(start:slen)
      end if

   end subroutine split_string

   ! ---------------------------------------------------------------------------
   integer function find_col(headers, n_cols, target) result(idx)
      character(len=64), intent(in) :: headers(:)
      integer, intent(in)           :: n_cols
      character(len=*), intent(in)  :: target
      integer :: j

      idx = -1
      do j = 1, n_cols
         if (trim(headers(j)) == trim(target)) then
            idx = j; return
         end if
      end do

   end function find_col

end program colors_post_proc