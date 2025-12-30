# ============================================================================
# SCRIPT 12: AUTOMATIZACIÓN MAESTRA CON GMAT
# ============================================================================
# Archivo: procedures/operations/master_automation.rb

load_utility 'ground_station_library'
require 'json'

class GroundStationMasterAutomation
  
  def initialize
    @schedule_file = File.join(Cosmos::USERPATH, 'outputs', 'planning', 'pass_schedule.json')
    @scheduler_file = File.join(Cosmos::USERPATH, 'outputs', 'pass_schedule.json')
    @passes = []
    @executed_passes = {}
    @automation_active = true
    
    puts "="*70
    puts "AUTOMATIZACIÓN MAESTRA - ESTACIÓN TERRENA CHASQUI_II"
    puts "="*70
  end
  
  def start
    puts "\n[INIT] Inicializando automatización maestra..."
    
    # Cargar calendario
    unless load_schedule()
      puts "\n✗ No se pudo cargar calendario de pases"
      puts "\nOpciones:"
      puts "  1. Ejecutar: procedures/operations/gmat_calendar_import.rb"
      puts "  2. O usar: procedures/operations/pass_scheduler.rb"
      return false
    end
    
    puts "\n✓ Sistema inicializado"
    display_schedule_summary()
    
    # Confirmación
    puts "\n⚠ La automatización ejecutará pases automáticamente"
    puts "Presione ENTER para continuar o Ctrl+C para cancelar..."
    gets
    
    # Iniciar loop principal
    main_loop()
  end
  
  def load_schedule
    # Intentar cargar desde pass_scheduler.rb primero
    if File.exist?(@scheduler_file)
      begin
        scheduler_data = JSON.parse(File.read(@scheduler_file), symbolize_names: true)
        @passes = scheduler_data.sort_by { |p| p[:aos] }
        puts "✓ Calendario cargado desde pass_scheduler (#{@passes.length} pases)"
        return true
      rescue => e
        puts "⚠ Error cargando scheduler: #{e.message}"
      end
    end
    
    # Si no, intentar GMAT
    if File.exist?(@schedule_file)
      begin
        gmat_data = JSON.parse(File.read(@schedule_file), symbolize_names: true)
        @passes = gmat_data.sort_by { |p| Time.parse(p[:aos]).to_i }
        puts "✓ Calendario cargado desde GMAT (#{@passes.length} pases)"
        return true
      rescue => e
        puts "⚠ Error cargando GMAT: #{e.message}"
      end
    end
    
    return false
  end
  
  def display_schedule_summary
    puts "\n" + "="*70
    puts "RESUMEN DEL CALENDARIO"
    puts "="*70
    
    now = Time.now
    upcoming = @passes.select do |p|
      pass_time = p[:aos].is_a?(Integer) ? Time.at(p[:aos]) : Time.parse(p[:aos])
      pass_time > now
    end
    
    puts "Total de pases: #{@passes.length}"
    puts "Pases futuros: #{upcoming.length}"
    
    if upcoming.any?
      puts "\nPróximos 5 pases:"
      puts "-"*70
      
      upcoming.first(5).each do |pass_info|
        aos = pass_info[:aos].is_a?(Integer) ? Time.at(pass_info[:aos]) : Time.parse(pass_info[:aos])
        time_to = ((aos - now) / 3600.0).round(1)
        
        pass_num = pass_info[:pass_number] || pass_info[:id]
        duration = pass_info[:duration] || pass_info[:duration_minutes]
        max_el = pass_info[:max_elevation]
        
        puts "  Pass #{pass_num}: #{aos.strftime('%m/%d %H:%M')} " \
             "(#{time_to}h) - #{duration}min - El:#{max_el}°"
      end
    end
    
    puts "="*70
  end
  
  def main_loop
    puts "\n[AUTOMATION] Iniciando monitoreo automático..."
    puts "Presione Ctrl+C para detener\n"
    
    loop_count = 0
    
    loop do
      begin
        loop_count += 1
        current_time = Time.now
        
        # Recargar calendario cada hora
        if loop_count % 120 == 0  # Cada hora (30s * 120)
          puts "\n[AUTO] Recargando calendario..."
          load_schedule()
        end
        
        # Buscar próximo pase
        next_pass = find_next_pass(current_time)
        
        unless next_pass
          print "\r[#{current_time.strftime('%H:%M:%S')}] ⏸  No hay pases programados"
          STDOUT.flush
          wait(30)
          next
        end
        
        # Procesar pase
        process_pass(next_pass, current_time)
        
        wait(30)  # Verificar cada 30 segundos
        
      rescue Interrupt
        puts "\n\n[AUTO] ⏹  Automatización detenida por usuario"
        break
        
      rescue => e
        puts "\n[AUTO] ✗ Error: #{e.message}"
        puts e.backtrace.first(3).join("\n")
        wait(60)
      end
    end
    
    puts "\n✓ Automatización finalizada"
  end
  
  def find_next_pass(current_time)
    @passes.find do |pass_info|
      # Convertir timestamp
      if pass_info[:los].is_a?(Integer)
        los_time = Time.at(pass_info[:los])
      else
        los_time = Time.parse(pass_info[:los])
      end
      
      los_time > current_time
    end
  end
  
  def process_pass(pass_info, current_time)
    # Convertir timestamps
    if pass_info[:aos].is_a?(Integer)
      aos_time = Time.at(pass_info[:aos])
      los_time = Time.at(pass_info[:los])
    else
      aos_time = Time.parse(pass_info[:aos])
      los_time = Time.parse(pass_info[:los])
    end
    
    time_to_aos = aos_time - current_time
    pass_id = pass_info[:pass_number] || pass_info[:id]
    duration = pass_info[:duration] || pass_info[:duration_minutes]
    max_el = pass_info[:max_elevation]
    
    # FASE 1: MÁS DE 30 MINUTOS ANTES
    if time_to_aos > 1800
      mins_to_aos = (time_to_aos / 60).round(0)
      print "\r[#{current_time.strftime('%H:%M:%S')}] ⏳ Próximo pase en #{mins_to_aos} min (Pass #{pass_id})"
      STDOUT.flush
      return
    end
    
    # FASE 2: 15-30 MINUTOS ANTES (Pre-pase)
    if time_to_aos > 900 && time_to_aos <= 1800
      unless @executed_passes["#{pass_id}_prep"]
        execute_pre_pass(pass_info, aos_time, duration, max_el)
        @executed_passes["#{pass_id}_prep"] = true
      else
        mins = (time_to_aos / 60).round(1)
        print "\r[#{current_time.strftime('%H:%M:%S')}] 🔧 Pre-pase completado. AOS en #{mins} min"
        STDOUT.flush
      end
      return
    end
    
    # FASE 3: 0-15 MINUTOS ANTES (Countdown)
    if time_to_aos > 0 && time_to_aos <= 900
      mins = (time_to_aos / 60).to_i
      secs = (time_to_aos % 60).to_i
      print "\r[#{current_time.strftime('%H:%M:%S')}] ⏰ COUNTDOWN Pass #{pass_id}: #{mins}:#{secs.to_s.rjust(2,'0')}"
      STDOUT.flush
      return
    end
    
    # FASE 4: DURANTE EL PASE
    if current_time >= aos_time && current_time <= los_time
      unless @executed_passes["#{pass_id}_active"]
        execute_pass(pass_info)
        @executed_passes["#{pass_id}_active"] = true
      else
        elapsed = ((current_time - aos_time) / 60).round(1)
        print "\r[#{current_time.strftime('%H:%M:%S')}] 🛰️  PASE ACTIVO (#{elapsed}/#{duration} min)"
        STDOUT.flush
      end
      return
    end
    
    # FASE 5: POST-PASE (0-10 minutos después)
    if current_time > los_time && current_time <= (los_time + 600)
      unless @executed_passes["#{pass_id}_post"]
        execute_post_pass(pass_info)
        @executed_passes["#{pass_id}_post"] = true
      else
        print "\r[#{current_time.strftime('%H:%M:%S')}] 📊 Post-pase completado"
        STDOUT.flush
      end
      return
    end
  end
  
  def execute_pre_pass(pass_info, aos_time, duration, max_el)
    puts "\n\n" + "="*70
    puts "🔧 FASE PRE-PASE"
    puts "="*70
    puts "Pass: #{pass_info[:pass_number] || pass_info[:id]}"
    puts "AOS:  #{aos_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "="*70
    
    begin
      # Cargar script de pre-pase
      load File.join(Cosmos::USERPATH, 'config', 'targets', 'CHASQUI_II', 
                     'procedures', 'operations', 'pre_pass.rb')
      
      result = pre_pass_checks(aos_time, duration, max_el)
      
      if result
        puts "\n✓ Pre-pase completado exitosamente"
      else
        puts "\n⚠ Pre-pase con advertencias"
      end
      
    rescue => e
      puts "\n✗ Error en pre-pase: #{e.message}"
    end
  end
  
  def execute_pass(pass_info)
    puts "\n\n" + "="*70
    puts "🛰️  INICIANDO PASE ACTIVO"
    puts "="*70
    
    aos_time = pass_info[:aos].is_a?(Integer) ? Time.at(pass_info[:aos]) : Time.parse(pass_info[:aos])
    duration = pass_info[:duration] || pass_info[:duration_minutes]
    
    # Determinar si usar comandos automáticos
    auto_commands = pass_info[:auto_commands] != false
    auto_download = pass_info[:auto_download] != false
    
    puts "Auto-comandos: #{auto_commands ? 'HABILITADO' : 'DESHABILITADO'}"
    puts "Auto-descarga: #{auto_download ? 'HABILITADO' : 'DESHABILITADO'}"
    puts "="*70
    
    begin
      # Cargar script de pase activo
      load File.join(Cosmos::USERPATH, 'config', 'targets', 'CHASQUI_II', 
                     'procedures', 'operations', 'during_pass.rb')
      
      monitor_pass_real_time(
        auto_commands: auto_commands,
        auto_download: auto_download
      )
      
      puts "\n✓ Pase completado"
      
    rescue => e
      puts "\n✗ Error durante pase: #{e.message}"
    end
  end
  
  def execute_post_pass(pass_info)
    puts "\n\n" + "="*70
    puts "📊 FASE POST-PASE"
    puts "="*70
    
    begin
      # Esperar que se escriban todos los logs
      wait(5)
      
      # Cargar script de post-pase
      load File.join(Cosmos::USERPATH, 'config', 'targets', 'CHASQUI_II', 
                     'procedures', 'operations', 'post_pass.rb')
      
      post_pass_analysis()
      
      puts "\n✓ Post-pase completado"
      
    rescue => e
      puts "\n✗ Error en post-pase: #{e.message}"
    end
  end
  
end

# Ejecución desde Script Runner
if __FILE__ == $0
  automation = GroundStationMasterAutomation.new
  automation.start
end