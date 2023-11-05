﻿create database DMS
go
use DMS
go
set datefirst 7
go

create or alter proc _createTables as
begin tran
	set xact_abort on
	set nocount on

	begin try
		create table admin(
			id uniqueidentifier default(newid()) primary key,
			name nvarchar(64) not null check(len(name) > 0),
			password nvarchar(64) not null,
			phone nchar(10) unique not null check(isnumeric(phone) = 1 and len(phone) = 10)
		)

		create table staff(
			id uniqueidentifier default(newid()) primary key,
			name nvarchar(64) not null check(len(name) > 0),
			password nvarchar(64) not null,
			phone nchar(10) unique not null check(isnumeric(phone) = 1 and len(phone) = 10),
			gender nvarchar(8) check(gender is null or gender in ('male', 'female')),
			isLocked bit not null default(0)
		)

		create table patient(
			id uniqueidentifier default(newid()) primary key,
			name nvarchar(64) not null check(len(name) > 0),
			password nvarchar(64) not null default('DMS123'),
			phone nchar(10) unique not null check(isnumeric(phone) = 1 and len(phone) = 10),
			gender nvarchar(8) check(gender is null or gender in ('male', 'female')),
			isLocked bit not null default(0),
			dob date not null check(dob < getdate()),
			address nvarchar(128) not null check(len(address) > 0),
		)

		create table dentist(
			id uniqueidentifier default(newid()) primary key,
			name nvarchar(64) not null check(len(name) > 0),
			password nvarchar(64) not null,
			phone nchar(10) unique not null check(isnumeric(phone) = 1 and len(phone) = 10),
			gender nvarchar(8) check(gender is null or gender in ('male', 'female')),
			isLocked bit not null default(0),
		)

		create table dentistSchedule(
			dentistId uniqueidentifier not null foreign key references dentist(id),
			shift nvarchar(16) not null check(shift in ('morning', 'afternoon', 'evening')),
			date int not null check(1 <= date and date <= 7),
			constraint pkDentistSchedule primary key(dentistId, shift, date)
		)

		create table appointment(
			dentistId uniqueidentifier not null foreign key references dentist(id),
			patientId uniqueidentifier not null foreign key references patient(id),
			shift nvarchar(16) not null check(shift in ('morning', 'afternoon', 'evening')),
			date date not null check(getdate() < date),
			status nvarchar(16) not null check(status in ('pending', 'confirmed', 'cancelled')),
			constraint pkAppointment primary key(dentistId, shift, date),
			constraint uqAppointment unique(patientId, shift, date)
		)

		create table service(
			id uniqueidentifier default(newid()) primary key,
			name nvarchar(64) unique not null check(len(name) > 0),
			description nvarchar(1024) not null,
			price int not null check(price > 0)
		)

		create table drug(
			id uniqueidentifier default(newid()) primary key,
			name nvarchar(64) unique not null check(len(name) > 0),
			directive nvarchar(512) not null,
			price int not null check(price > 0),
			unit nvarchar(64) not null check(len(unit) > 0),
		)

		create table drugBatch(
			drugId uniqueidentifier not null foreign key references drug(id),
			expirationDate date not null,
			import int not null check(import > 0),
			isRemoved bit not null default(0),
			stock int,
			constraint pkDrugBatch primary key(drugId, expirationDate)
		)

		create table prescribedDrug(
			prescriptionId uniqueidentifier not null,
			drugId uniqueidentifier not null,
			expirationDate date not null,
			dosage nvarchar(64) not null check(len(dosage) > 0),
			quantity float not null check(quantity > 0),

			constraint pkPrescribedDrug primary key(
				prescriptionId, drugId, expirationDate
			)
		)

		alter table prescribedDrug
			add foreign key (drugId, expirationDate)
			references drugBatch(drugId, expirationDate)

		create table prescription(
			id uniqueidentifier default(newid()) primary key,
			total int
		)

		alter table prescribedDrug
			add foreign key (prescriptionId) references prescription(id)

		create table treatedService(
			treatmentId uniqueidentifier not null,
			serviceId uniqueidentifier not null foreign key references service(id),
			constraint pktreatedService primary key(treatmentId, serviceId)
		)

		create table treatment(
			id uniqueidentifier default(newid()) primary key,

			dentistId uniqueidentifier not null foreign key references dentist(id),
			shift nvarchar(16) not null check(shift in ('morning', 'afternoon', 'evening')),
			date date not null,

			prescriptionId uniqueidentifier foreign key references prescription(id),

			symptoms nvarchar(64) not null,
			notes nvarchar(64) not null,
			toothTreated nvarchar(64) not null,
			outcome nvarchar(16) not null,
			treatmentCharge int not null check(treatmentCharge > 0),
			totalServiceCharge int
		)

		alter table treatment
			add foreign key (dentistId, shift, date)
			references appointment(dentistId, shift, date)

		alter table treatedService
			add foreign key (treatmentId) references treatment(id)

		create table invoice(
			id uniqueidentifier default(newid()) primary key,
			treatmentId uniqueidentifier not null foreign key references treatment(id),
			issueDate date not null default(getdate()),
			total int
		)
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go
exec _createTables
go

create or alter function dbo._checkPassword(@password nvarchar(64)) returns bit as
begin
	if
		len(@password) <= 8 or
		@password not like '%[0-9]%' or
		@password not like '%[a-z]%' or @password not like '%[A-Z]%'
	begin
		return 0
	end

	return 1
end

go

create or alter function dbo._checkInvoiceOfTreatment(
	@treatmentId uniqueidentifier,
	@date date
)
returns bit as
begin
	declare @issueDate date
	select @issueDate = issueDate from invoice where treatmentId = @treatmentId

	if
		@treatmentId is not null and @issueDate is not null and
		@issueDate < (select date from treatment t where t.id = @treatmentId)
	begin
		return 0
	end

	return 1
end

go

create or alter function dbo._calculateInvoiceTotal(@treatmentId uniqueidentifier)
returns int as
begin
	declare @treatmentCharge int, @totalServiceCharge int
	declare @prescriptionId uniqueidentifier, @totalPrescriptionCharge int
	select
		@treatmentCharge = treatmentCharge,
		@totalServiceCharge = totalServiceCharge,
		@prescriptionId = prescriptionId
	from treatment where id = @treatmentId
	select @totalPrescriptionCharge = total from prescription where id = @prescriptionId

	return (@treatmentCharge + @totalServiceCharge + @totalPrescriptionCharge)
end

go

create or alter function dbo._calculateServiceTotal(@treatmentId uniqueidentifier)
returns int as
begin
	return (
		select coalesce(sum(price), 0) from treatedService ts
		join service s on ts.serviceId = s.id
		where ts.treatmentId = @treatmentId
	)
end

go

create or alter function dbo._calculatePrescriptionTotal(@prescriptionId uniqueidentifier)
returns int as
begin
	return (
		select coalesce(sum(price * quantity), 0) from prescribedDrug pd
		join drug d on pd.drugId = d.id
		where pd.prescriptionId = @prescriptionId
	)
end

go

create or alter function dbo._calculateDrugStock(
	@drugId uniqueidentifier,
	@expirationDate date
)
returns int as
begin
	return (
		(select import from drugBatch where drugId = @drugId and expirationDate = @expirationDate) -
		(select coalesce(sum(quantity), 0) from prescribedDrug where drugId = @drugId and expirationDate = @expirationDate)
	)
end

go

create or alter function dbo._checkDrugStock(
	@drugId uniqueidentifier,
	@expirationDate date,
	@quantity float
)
returns int as
begin
	declare @import int, @stock int, @isRemoved bit
	select
		@import = import,
		@stock = stock,
		@isRemoved = isRemoved
	from drugBatch where drugId = @drugId and expirationDate = @expirationDate

	if @stock < 0 or @isRemoved = 1
	begin
		return 0
	end

	return 1
end

go

create or alter function dbo._checkAppointmentTime(
	@dentistId uniqueidentifier,
	@shift nvarchar(16),
	@date date = null,
	@day int = null
)
returns int as
begin
	if exists(select * from appointment a where a.dentistId = @dentistId and (
		datepart(dw, a.date) not in (select date from dentistSchedule where dentistId = @dentistId) or
		a.shift not in (select shift from dentistSchedule where dentistId = @dentistId and date = datepart(dw, a.date))
	))
	begin
		return 0
	end

	return 1
end

go

create or alter trigger onDentistScheduleDelete
on dentistSchedule instead of delete as
begin
	set xact_abort on
	set nocount on

	if exists(
		select * from deleted d
		inner join dentistSchedule ds on
			ds.dentistId = d.dentistId and
			ds.shift = d.shift and ds.date = d.date
		join appointment a on
			a.dentistId = ds.dentistId and
			datepart(dw, a.date) = ds.date and
			a.shift = ds.shift
	)
	begin
		rollback tran;
		throw 51000, 'Schedule cannot be deleted because there exists appointments taking place on that day', 1
	end

	delete dentistSchedule from deleted d inner join dentistSchedule ds on
		ds.dentistId = d.dentistId and
		ds.date = d.date and ds.shift = d.shift
end

go

create or alter proc _createConstraints as
begin tran
	set xact_abort on
	set nocount on

	begin try
		alter table admin add check(dbo._checkPassword(password) = 1)
		alter table staff add check(dbo._checkPassword(password) = 1)
		alter table patient add check(dbo._checkPassword(password) = 1)
		alter table dentist add check(dbo._checkPassword(password) = 1)

		alter table invoice drop column total
		alter table invoice
		add total as dbo._calculateInvoiceTotal(treatmentId)

		alter table treatment drop column totalServiceCharge
		alter table treatment
		add totalServiceCharge as dbo._calculateServiceTotal(id)

		alter table prescription drop column total
		alter table prescription
		add total as dbo._calculatePrescriptionTotal(id)

		alter table drugBatch drop column stock
		alter table drugBatch
		add stock as dbo._calculateDrugStock(drugId, expirationDate)
		alter table prescribedDrug add check(dbo._checkDrugStock(drugId, expirationDate, quantity) = 1)

		alter table invoice add check(dbo._checkInvoiceOfTreatment(treatmentId, issueDate) = 1)
		alter table treatment add check(dbo._checkInvoiceOfTreatment(id, date) = 1)

		alter table appointment add check(dbo._checkAppointmentTime(dentistId, shift, date, null) = 1)
		alter table dentistSchedule add check(dbo._checkAppointmentTime(dentistId, shift, null, date) = 1)
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go
exec _createConstraints
go

create or alter proc getUserByCred(
	@phone nchar(10),
	@password nvarchar(64),
	@role nvarchar(16)
)
with execute as owner
as
begin tran
	set xact_abort on
	set nocount on

	begin try
		declare @sql nvarchar(128) =
			'select * from ' + @role + ' where phone = @phone and password = @password'

		exec sp_executesql @sql,
			N'@phone nchar(10), @password nvarchar(64)',
			@phone = @phone, @password = @password
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getPatientByPhone(@phone nchar(10)) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc createPatient(
	@name nvarchar(64),
	@password nvarchar(64),
	@phone nchar(10),
	@gender nvarchar(8),
	@dob date,
	@address nvarchar(128)
) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		insert into patient(name, password, phone, gender, dob, address)
			values (@name, @password, @phone, @gender, @dob, @address)

		select * from patient where phone = @phone
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc createGuestPatient(
	@name nvarchar(64),
	@phone nchar(10),
	@gender nvarchar(8),
	@dob date,
	@address nvarchar(128)
) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		insert into patient(name, phone, gender, dob, address)
			values (@name, @phone, @gender, @dob, @address)

		select * from patient where phone = @phone
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc createStaff as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc createDentist as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc lockUser as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getDentists as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getDentistDetails(@id uniqueidentifier) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc bookAppointment(
	@dentistId uniqueidentifier,
	@patientId uniqueidentifier,
	@date date
) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getDentistsOnShift(
	@date date,
	@shift nvarchar(16)
) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc updatePatient as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getPatientDetails(@id uniqueidentifier) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc addDentistSchedule as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc removeDentistSchedule as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getDrugs as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getDrugDetails(@id uniqueidentifier) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getServices as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc getServiceDetails(@id uniqueidentifier) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc createDrug as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc updateDrug as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc deleteDrug as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc addDrugBatch as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc removeDrugBatch as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc createInvoice as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

-- Giải quyết RBTV: Mỗi đơn điều trị phải có ít nhất một dịch vụ
create or alter proc createTreatment(
	@serviceId uniqueidentifier
) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc addServiceToTreatment(
	@treatmentId uniqueidentifier,
	@serviceId uniqueidentifier
) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

-- Giải quyết RBTV:
-- 1. Mỗi đơn thuốc được kê phải thuộc về một đơn điều trị hợp lệ
-- 2. Mỗi đơn thuốc có ít một loại thuốc
create or alter proc addPrescriptionToTreatment(
	@treatmentId uniqueidentifier,
	@drugId uniqueidentifier,
	@expirationDate date,
	@dosage nvarchar(64),
	@quantity int
) as
begin tran
	set xact_abort on
	set nocount on

	begin try
		print 'Do something'
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go

create or alter proc _createServerUsers as
begin tran
	set xact_abort on
	set nocount on

	begin try
		if not exists (select loginname from master.dbo.syslogins where name = 'guest')
			create login guest with password = 'guest'

		if not exists (select loginname from master.dbo.syslogins where name = 'patient')
			create login patient with password = 'patient'

		if not exists (select loginname from master.dbo.syslogins where name = 'dentist')
			create login dentist with password = 'dentist'

		if not exists (select loginname from master.dbo.syslogins where name = 'staff')
			create login staff with password = 'staff'

		if not exists (select loginname from master.dbo.syslogins where name = 'admin')
			create login admin with password = 'admin'

		create user guestUser for login guest
		create user patientUser for login patient
		create user dentistUser for login dentist
		create user staffUser for login staff
		create user adminUser for login admin

		create role guests
		create role patients
		create role dentists
		create role staffs
		create role admins

		alter role guests add member guestUser
		alter role patients add member patientUser
		alter role dentists add member dentistUser
		alter role staffs add member staffUser
		alter role admins add member adminUser

		grant exec on dbo.getUserByCred to guests
		grant exec on dbo.createPatient to guests
		grant exec on dbo.createGuestPatient to guests
		grant exec on dbo.getDentists to guests
		grant exec on dbo.getDentistDetails to guests
		grant exec on dbo.bookAppointment to guests
		grant exec on dbo.getDentistsOnShift to guests
		grant exec on dbo.getServices to guests
		grant exec on dbo.getServiceDetails to guests

		grant exec on dbo.getDentists to patients
		grant exec on dbo.getDentistDetails to patients
		grant exec on dbo.bookAppointment to patients
		grant exec on dbo.getDentistsOnShift to patients
		grant exec on dbo.getServices to patients
		grant exec on dbo.getServiceDetails to patients
		grant exec on dbo.getUserByCred to patients
		grant exec on dbo.updatePatient to patients
		grant exec on dbo.getPatientDetails to patients

		grant exec on dbo.getPatientByPhone to dentists
		grant exec on dbo.getPatientDetails to dentists
		grant exec on dbo.getServices to dentists
		grant exec on dbo.getServiceDetails to dentists
		grant exec on dbo.getDrugs to dentists
		grant exec on dbo.getDrugDetails to dentists
		grant exec on dbo.createTreatment to dentists
		grant exec on dbo.addServiceToTreatment to dentists
		grant exec on dbo.addPrescriptionToTreatment to dentists
		grant exec on dbo.getDentistDetails to dentists
		grant exec on dbo.addDentistSchedule to dentists
		grant exec on dbo.removeDentistSchedule to dentists

		grant exec on dbo.createGuestPatient to staffs
		grant exec on dbo.getPatientByPhone to staffs
		grant exec on dbo.getDentists to staffs
		grant exec on dbo.getDentistDetails to staffs
		grant exec on dbo.bookAppointment to staffs
		grant exec on dbo.getDentistsOnShift to staffs
		grant exec on dbo.createInvoice to staffs
		grant exec on dbo.getDrugs to staffs
		grant exec on dbo.getDrugDetails to staffs

		grant exec on dbo.getDrugs to admins
		grant exec on dbo.getDrugDetails to admins
		grant exec on dbo.createDrug to admins
		grant exec on dbo.updateDrug to admins
		grant exec on dbo.deleteDrug to admins
		grant exec on dbo.addDrugBatch to admins
		grant exec on dbo.removeDrugBatch to admins
		grant exec on dbo.createStaff to admins
		grant exec on dbo.createDentist to admins
		grant exec on dbo.lockUser to admins
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go
exec _createServerUsers
go

create or alter proc _insertData as
begin tran
	set xact_abort on
	set nocount on

	begin try
		insert into admin(name, password, phone) values
			(N'Võ Nam Đăng', 'Admin12345', '0211260560'),
			(N'Nguyễn Văn A', 'P@ssw0rd1', '5551234567')

		insert into staff(name, password, phone, gender) values
			(N'Hồ Nguyễn Minh Thư', 'Staff12345', '0211260050', 'female'),
			(N'Nguyễn Văn X', 'P@ssw0rd1', '5551234567', 'male'),
			(N'Trần Thị Y', 'S3cr3tpwd', '5559876543', 'female')

		insert into dentist(name, password, phone, gender) values
			(N'Trần Ngọc Diễm Châu', 'Dentist12345', '0211260520', 'female'),
			(N'Lê Hữu Z', 'securepwd1', '5557890123', 'male'),
			(N'Phạm Thị W', 'pa$$12w0rd', '5552345678', 'female')

		insert into patient(name, password, phone, gender, dob, address) values
			(N'Trương Hoàng Kha', 'Patient12345', '0211260200', 'male', '2003-01-01', N'Thành phố Hồ Chí Minh'),
			(N'Nguyễn Thị A', 'P@ssw0rd1', '5551234567', 'female', '1990-05-15', N'123 Đường Chính, Thành phố, Quốc gia'),
			(N'Trần Văn B', 'S3cr3tPwd', '5559876543', 'male', '1985-09-20', N'456 Phố Elm, Thị trấn, Quốc gia'),
			(N'Lê Thị C', 'SecurePwd1', '5557890123', 'female', '1993-03-10', N'789 Đường Sồi, Làng, Quốc gia'),
			(N'Phạm Văn D', 'Pa$$12w0rd', '5552345678', 'male', '1988-12-05', N'567 Đường Bạch, Xã, Quốc gia')

		declare @dentistAId uniqueidentifier
		select @dentistAId = id from dentist where phone = '0211260520'
		declare @dentistBId uniqueidentifier
		select @dentistBId = id from dentist where phone = '5557890123'

		insert into dentistSchedule(dentistId, shift, date) values
			(@dentistAId, 'morning', 1),
			(@dentistAId, 'afternoon', 2),
			(@dentistAId, 'evening', 3),
			(@dentistAId, 'morning', 4),
			(@dentistAId, 'afternoon', 4),
			(@dentistBId, 'morning', 5),
			(@dentistBId, 'afternoon', 5),
			(@dentistBId, 'evening', 6),
			(@dentistBId, 'morning', 7),
			(@dentistBId, 'afternoon', 7)

		declare @patientAId uniqueidentifier
		select @patientAId = id from patient where phone = '0211260200'
		declare @patientBId uniqueidentifier
		select @patientBId = id from patient where phone = '5551234567'

		insert into appointment(dentistId, patientId, shift, date, status) values
			(@dentistAId, @patientAId, 'afternoon', '2023-12-04', 'confirmed'),
			(@dentistAId, @patientBId, 'afternoon', '2023-12-11', 'pending'),
			(@dentistBId, @patientAId, 'morning', '2023-12-14', 'pending')

		insert into service(name, price, description) values
			('Dental bracing', 40000000, 'Bracing is a method of using specialized appliances that are fixed or removable on teeth to help move and align teeth to the correct positions. Thus giving customers even, beautiful teeth, ensuring proper chewing and biting function.'),
			('Dental implant', 20000000, 'Implants are the most effective solution to restore lost teeth as they not only help restore tooth aesthetics and ensure normal chewing ability, but dental implants also have the ability to maintain sustainability with many outstanding advantages.'),
			('Dental crowning', 8000000, 'Dental crowning is a fixed restoration technique using ceramic material that restores chewing function and improves aesthetics, helping you be confident with a naturally radiant smile.'),
			('Dental veneers', 8000000, 'Dental veneer is a porcelain veneer used to cover the outside of the tooth surface to cover up defects when the tooth structure is damaged or is dull or yellow, giving customers even, beautiful, bright white teeth.'),
			('Teeth whitening', 3000000, 'Teeth whitening is a method using oxidation to cut off the color molecular chains in dentin. This helps teeth become whiter and brighter than the original tooth color without damaging the tooth surface or any element in the tooth.'),
			('Wisdom tooth extraction', 3000000, 'Wisdom teeth often grow crookedly or crowd adjacent teeth, creating discomfort and leading to a number of dental diseases. By applying modern technology in wisdom tooth extraction, we can help the tooth be removed gently and safely.'),
			('Dental fillings', 500000, 'Dental filling is a technique in which filling material is used to restore the shape and function of the tooth. This method is meaningful in both aesthetics and the treatment and prevention of oral diseases.'),
			('Root canal treatment', 2000000, 'Root canal treatment plays an important role in nurturing strong teeth. Therefore, we need timely root canal treatment to avoid consequences affecting oral health.'),
			('Periodontitis treatment', 5000000, 'Periodontal disease is a gum infection that damages soft tissue and destroys the bone around the teeth. If the infection becomes severe, it can cause the tooth to become loose or lead to tooth loss. Periodontitis treatment must be performed as soon as possible because it will greatly affect oral health.')

		insert into drug(name, price, unit, directive) values
			('Amoxicillin', 8000, 'tablet (500mg)', 'Use for infections caused by susceptible bacteria, gonorrhea, and gastroenteritis. Do not use for patients with a history of allergy to any type of penicillin or any ingredient of the drug.'),
			('Cephalexin', 10000, 'tablet (500mg)', 'Use for infections caused by susceptible bacteria, but not for the treatment of severe infections. Do not use for patients with a history of allergy to cephalosporin antibiotics.'),
			('Clindamycin', 21000, 'tablet (300mg)', 'Use for severe infections due to anaerobic bacteria and treatment of diseases caused by Gram-positive bacteria. Do not use for patients who are sensitive to Clindamycin, Lincomycin or any ingredient of the drug.'),
			('Azithromycin', 45000, 'tablet (500mg)', 'Use for infections caused by drug-sensitive bacteria such as lower respiratory tract infections and upper respiratory infections. Do not use for patients with hypersensitivity to Azithromycin or any macrolide antibiotic.'),
			('Paracetamol', 5000, 'tablet (500mg)', 'Use for treatment of mild to moderate pain and reducing symptoms of rheumatic pain, flu, fever and colds. Do not use for patients with hypersensitivity to paracetamol or any ingredient of the drug.'),
			('Aspirin', 6000, 'tablet (500mg)', 'Use for pain relief in cases of: muscle pain, back pain, sprains, toothache, fractures, dislocations, or pain after surgery. Do not use for patients with a history of asthma, hypersensitivity to any ingredient of the drug, hemophilia, thrombocytopenia, progressive gastric or duodenal ulcer, heart failure, liver failure, or kidney failure.'),
			('Ibuprofen', 10000, 'tablet (400mg)', 'Use for symptomatic treatment of painful diseases. Do not use for patients with hypersensitivity to ibuprofen and similar substances, progressive gastric and duodenal ulcers, severe liver cell failure, severe kidney failure, children under 15 years old, pregnant women in the first and last 3 months pregnancy, lactating women.'),
			('Cefixim', 31000, 'tablet (200mg)', 'Use for infections caused by susceptible strains of bacteria, pharyngitis and tonsillitis caused by Streptococcus pyogenes. Do not use for patients with a history of allergic shock to drugs or hypersensitivity to any cephalosporin or penicillin or any ingredient of the medicine.'),
			('Clarithromycin', 39000, 'tablet (500mg)', 'Use for infections caused by susceptible bacteria and Helicobacter pylori eradication treatment in duodenal ulcer patients. Do not use for patients with a history of QT prolongation, ventricular arrhythmia with torsades de pointes, severe liver failure, or hypersensitivity to clarithromycin, erythromycin or any other macrolide antibiotic or any ingredient of the drug. Concomitant use of clarithromycin with certain drugs such as terfenadine, astemizole, cisapride, pimozide,... is contraindicated.'),
			('Acyclovir', 20000, 'tablet (800mg)', 'Use for treatment of Herpes simplex infections of the skin and mucous membranes including primary and recurrent genital herpes infections, and treatment of Varicella infection (chickenpox) and Herpes zoster infection (shingles). Do not use for patients with hypersensitivity to acyclovir and valacyclovir.'),
			('Medoral', 96000, 'bottle (250ml)', 'Use for inflammation prevention, infections in the throat/mouth, dental hygiene, wound healing after surgery or dental treatment, and denture control. Dot not use for patients who are allergic to any ingredient of Medoral'),
			('Eludril', 80000, 'bottle (90ml)', 'Use for local adjunctive treatment of oral infections and dental and oral postoperative care. Do not use for patients with allergy to chlorhexidine, chlorobutanol or other ingredients of the drug.'),
			('Fluconazole', 13000, 'box (150mg)', 'Use for coccidioides immitis fungal infection and Mucosal candidiasis including oropharyngeal candidiasis, esophageal candidiasis, urinary candidiasis, and mucocutaneous candidiasis. Do not use for patients with hypersensitivity to fluconazole, azole antifungals or any ingredient of the drug.'),
			('Nystatin', 20000, 'box (2 tablets)', 'Use for treatment of Candida albicans fungal infections of the oral mucosa and pharynx. Do not use for patients hypersensitive to one of the ingredients of the drug.')

		declare @amoxicillinId uniqueidentifier
		select @amoxicillinId = id from drug where name = 'Amoxicillin'
		declare @medoralId uniqueidentifier
		select @medoralId = id from drug where name = 'Medoral'

		insert into drugBatch(drugId, expirationDate, import) values
			(@amoxicillinId, '2023-12-12', 10),
			(@medoralId, '2023-12-10', 5)

		insert into prescription default values

		declare @prescriptionId uniqueidentifier
		select @prescriptionId = id from prescription

		insert into prescribedDrug(prescriptionId, drugId, expirationDate, dosage, quantity) values
			(@prescriptionId, @amoxicillinId, '2023-12-12', '1 pill every morning, 1 pill every afternoon', 2),
			(@prescriptionId, @medoralId, '2023-12-10', '100ml every morning', 1)

		insert into treatment(
			dentistId, shift, date,
			prescriptionId, symptoms, notes, toothTreated, outcome, treatmentCharge
		) values
			(
				@dentistAId, 'afternoon', '2023-12-04',
				@prescriptionId, 'None', 'None', 'Wisdom tooth', 'Success', 100000
			)

		declare @treatmentId uniqueidentifier
		select @treatmentId = id from treatment where toothTreated = 'Wisdom tooth'

		declare @serviceId uniqueidentifier
		select @serviceId = id from service where name = 'Wisdom tooth extraction'

		insert into treatedService(treatmentId, serviceId) values
			(@treatmentId, @serviceId)

		insert into invoice(treatmentId, issueDate) values
			(@treatmentId, '2023-12-04')
	end try
	begin catch
		rollback tran;
		throw
	end catch
commit tran

go
exec _insertData
go