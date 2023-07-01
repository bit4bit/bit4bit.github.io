# coding: utf-8
require 'spec_helper'
require 'tempfile'
require 'open3'
require 'timeout'
require 'net/ftp'

def validate_syntax(config_path)
  %x[timeout 1 vsftpd -olisten_port=0 -olisten=YES -orun_as_launching_user=YES #{config_path}]
  $?.exitstatus == 0 || $?.exitstatus == 124
end

def vsftpd_start(config_path)
  pid = Process.spawn("vsftpd -olisten_port=0 -olisten=YES -orun_as_launching_user=YES #{config_path}")
  Process.detach(pid)

  sleep 1

  port = %x{lsof -p #{pid} -itcp -a -P -n}.chomp[/TCP.+:(\d+)/,1].to_i

  {pid: pid, port: port}
end

def vsftpd_alive?(server)
  # http://dev.housetrip.com/2014/03/24/ruby-pid-tip/
  Process.kill(0, server[:pid])
  true
rescue Errno::ESRCH
  false
end

def vsftpd_stop(server)
  Process.kill(9, server[:pid])
rescue Errno::ESRCH
  false
end

describe 'vsftpd' do
  let (:conf) { Tempfile.new('vsftpd') }
  
  describe 'configuracion' do
    it 'al verificar archivo invalido falla' do
      conf.write('invalidline')
      conf.flush
      
      expect(validate_syntax(conf.path)).to be false
    end

    it 'al verificar archivo valido ok' do
      conf.write('listen_ipv6=NO')
      conf.flush
      
      expect(validate_syntax(conf.path)).to be true
    end
  end

  describe 'gestión del servicio' do
    it 'iniciar cuando el archivo de configuracion es correcto' do
      conf.flush
      
      pid = vsftpd_start(conf.path)
      
      expect(vsftpd_alive?(pid)).to be true
    ensure
      vsftpd_stop(pid)
    end

    it 'not iniciar cuando el archivo de configuracion es invalido' do
      conf.write('asdfs')
      conf.flush

      pid = vsftpd_start(conf.path)
      expect(vsftpd_alive?(pid)).to be false
    ensure
      vsftpd_stop(pid)
    end
  end

  describe 'comportamiento' do
    it 'no se permite logeo anonimo' do
      conf.write('anonymous_enable=NO')
      conf.flush

      server = vsftpd_start(conf.path)

      expect do
        Net::FTP.open("127.0.0.1", port: server[:port]) do |ftp|
          ftp.login
        end
      end.to raise_error(Net::FTPPermError)
    ensure
      vsftpd_stop(server)
    end
  end
end
