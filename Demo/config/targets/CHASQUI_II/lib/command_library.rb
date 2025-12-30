require 'cosmos'
require 'cosmos/script'

module ChasquiII
  class CommandLibrary
    
    # ========================================
    # COMANDOS BÁSICOS
    # ========================================
    
    def self.send_noop
      """Enviar comando NOOP (heartbeat)"""
      cmd("CHASQUI_II NOOPERATION")
      wait_check_cmd_success("CHASQUI_II NOOPERATION", 5)
    end
    
    def self.request_static_params
      """Solicitar parámetros estáticos"""
      cmd("CHASQUI_II ISSUEPACKET with PACKET STATICPAR, STREAM DEBUG")
      wait(2)
      wait_packet("CHASQUI_II", "STATICPARS", 1, 10)
    end
    
    def self.request_dynamic_params
      """Solicitar parámetros dinámicos"""
      cmd("CHASQUI_II ISSUEPACKET with PACKET DYNAMICPAR, STREAM DEBUG")
      wait(2)
      wait_packet("CHASQUI_II", "DYNAMICPARS", 1, 10)
    end
    
    # ========================================
    # CONTROL DE MODO
    # ========================================
    
    def self.switch_to_safe(voltage_check: true)
      """
      Cambiar a modo SAFE
      Args:
        voltage_check: Verificar voltaje antes de cambiar
      """
      if voltage_check
        voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
        if voltage > 8.0
          puts "ADVERTENCIA: Voltaje alto (#{voltage}V), ¿seguro de cambiar a SAFE?"
          print "Continuar? (y/n): "
          return unless gets.chomp.downcase == 'y'
        end
      end
      
      cmd("CHASQUI_II SWITCHTOSAFE")
      wait(5)
      
      # Verificar cambio
      wait_check("CHASQUI_II BEACON SAT_CURR_MODE == 'SAFE'", 30)
      puts "✓ Modo SAFE activado"
    end
    
    def self.switch_to_nominal(voltage_check: true)
      """
      Cambiar a modo NOMINAL
      Args:
        voltage_check: Verificar voltaje antes de cambiar
      """
      if voltage_check
        voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
        if voltage < 7.5
          puts "ERROR: Voltaje muy bajo (#{voltage}V < 7.5V)"
          puts "No se puede cambiar a NOMINAL"
          return false
        end
      end
      
      cmd("CHASQUI_II SWITCHTONOMINAL")
      wait(5)
      
      # Verificar cambio
      begin
        wait_check("CHASQUI_II BEACON SAT_CURR_MODE == 'NOMINAL'", 30)
        puts "✓ Modo NOMINAL activado"
        return true
      rescue
        puts "✗ Error: No se pudo cambiar a NOMINAL"
        return false
      end
    end
    
    # ========================================
    # CONTROL DE PAYLOAD
    # ========================================
    
    def self.payload_on(temp_check: true)
      """
      Encender payload con verificaciones
      """
      if temp_check
        temp = tlm("CHASQUI_II BEACON TEMP_CDH")
        if temp > 45
          puts "ERROR: Temperatura muy alta (#{temp}°C)"
          return false
        end
      end
      
      cmd("CHASQUI_II TURNONPERIPHERAL with PERIPHERAL PL")
      wait(5)
      puts "✓ Payload encendido"
      return true
    end
    
    def self.payload_off
      """Apagar payload"""
      cmd("CHASQUI_II TURNOFFPERIPHERAL with PERIPHERAL PL")
      wait(2)
      puts "✓ Payload apagado"
    end
    
    # ========================================
    # PLAYBACK DE DATOS
    # ========================================
    
    def self.playback_data(partition, start_ptr: 0, num_packets: 50)
      """
      Realizar playback de datos almacenados
      Args:
        partition: Partición (BEACON, PL, etc)
        start_ptr: Puntero inicial
        num_packets: Número de paquetes
      """
      puts "Iniciando playback..."
      puts "  Partición: #{partition}"
      puts "  Inicio: #{start_ptr}"
      puts "  Paquetes: #{num_packets}"
      
      cmd("CHASQUI_II PLAYBACK with PARTITION #{partition}, READPOINTER #{start_ptr}, NPACKETS #{num_packets}")
      
      # Monitorear recepción
      received = 0
      timeout = num_packets * 2
      
      start_time = Time.now
      while received < num_packets && (Time.now - start_time) < timeout
        begin
          wait_packet("CHASQUI_II", "BEACON", 1, 2)
          received += 1
          print "\rRecibidos: #{received}/#{num_packets}"
        rescue Timeout::Error
          next
        end
      end
      
      puts "\n✓ Playback completado: #{received}/#{num_packets}"
      return received
    end
    
    def self.full_beacon_download
      """Descargar todos los beacons disponibles"""
      # Solicitar parámetros dinámicos para obtener punteros
      request_dynamic_params()
      wait(3)
      
      write_ptr = tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[0]")
      read_ptr = tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[0]")
      
      available = write_ptr - read_ptr
      
      if available <= 0
        puts "No hay beacons disponibles"
        return 0
      end
      
      puts "Beacons disponibles: #{available}"
      
      # Descargar en bloques de 50
      total_downloaded = 0
      blocks = (available / 50.0).ceil
      
      blocks.times do |i|
        start = read_ptr + (i * 50)
        count = [50, available - (i * 50)].min
        
        downloaded = playback_data("BEACON", start_ptr: start, num_packets: count)
        total_downloaded += downloaded
        
        wait(5)  # Pausa entre bloques
      end
      
      puts "✓ Descarga completa: #{total_downloaded} beacons"
      return total_downloaded
    end
    
    # ========================================
    # CONFIGURACIÓN
    # ========================================
    
    def self.configure_telemetry_intervals(eps: 10000, beacon: 30000, uhf: 5000)
      """
      Configurar intervalos de telemetría
      Args:
        eps: Intervalo EPS (ms)
        beacon: Intervalo beacon (ms)
        uhf: Intervalo UHF (ms)
      """
      puts "Configurando intervalos de telemetría..."
      
      cmd("CHASQUI_II SETEPSREADINTERVAL with INTERVAL #{eps}")
      wait(1)
      
      cmd("CHASQUI_II SETBCNPACKETINTERVAL with INTERVAL #{beacon}")
      wait(1)
      
      cmd("CHASQUI_II SETUHFREADINTERVAL with INTERVAL #{uhf}")
      wait(1)
      
      puts "✓ Intervalos configurados:"
      puts "  EPS: #{eps}ms"
      puts "  Beacon: #{beacon}ms"
      puts "  UHF: #{uhf}ms"
    end
    
    def self.set_mode_thresholds(exit_thresh: 8000, enter_thresh: 7500)
      """
      Configurar umbrales de modo
      Args:
        exit_thresh: Umbral de salida de SAFE (mV)
        enter_thresh: Umbral de entrada a SAFE (mV)
      """
      cmd("CHASQUI_II SETMODETHRESHOLDS with EXITTHRESH #{exit_thresh}, ENTERTHRESH #{enter_thresh}")
      wait(2)
      puts "✓ Umbrales configurados: Exit=#{exit_thresh}mV, Enter=#{enter_thresh}mV"
    end
    
    # ========================================
    # SECUENCIAS COMPLEJAS
    # ========================================
    
    def self.startup_sequence
      """Secuencia de inicio completa"""
      puts "="*60
      puts "SECUENCIA DE INICIO"
      puts "="*60
      
      # 1. Verificar comunicación
      puts "\n1. Verificando comunicación..."
      send_noop()
      
      # 2. Solicitar configuración actual
      puts "\n2. Solicitando configuración..."
      request_static_params()
      request_dynamic_params()
      
      # 3. Verificar estado de salud
      puts "\n3. Verificando salud del satélite..."
      voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
      mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
      temp = tlm("CHASQUI_II BEACON TEMP_CDH")
      
      puts "  Voltaje: #{voltage}V"
      puts "  Modo: #{mode}"
      puts "  Temperatura: #{temp}°C"
      
      # 4. Configurar intervalos óptimos
      puts "\n4. Configurando intervalos de telemetría..."
      configure_telemetry_intervals()
      
      puts "\n" + "="*60
      puts "✓ SECUENCIA DE INICIO COMPLETADA"
      puts "="*60
    end
    
    def self.safe_shutdown_sequence
      """Secuencia de apagado seguro"""
      puts "="*60
      puts "SECUENCIA DE APAGADO SEGURO"
      puts "="*60
      
      # 1. Apagar payload
      puts "\n1. Apagando payload..."
      payload_off()
      
      # 2. Reducir intervalos
      puts "\n2. Reduciendo intervalos de telemetría..."
      configure_telemetry_intervals(eps: 60000, beacon: 120000, uhf: 30000)
      
      # 3. Cambiar a modo SAFE
      puts "\n3. Cambiando a modo SAFE..."
      switch_to_safe(voltage_check: false)
      
      puts "\n" + "="*60
      puts "✓ APAGADO SEGURO COMPLETADO"
      puts "="*60
    end
    
  end
end