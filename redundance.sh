#!/bin/bash

# Script para fazer redundancia entre links de internet
# Neste script existem algumas formas diferentes de fazer o balanceamento, basicamente usando as funcoes : 
# - testPrimaryGw e testOnlyIf
#
# O script deve ficar com permissao de execucao e setado no CRON para rodar sempre
#
#date: 29/04/2015
#@by Samuel Dantas

export LC_ALL=C
export PATH=/bin:/usr/bin:/sbin:/usr/sbin 

# Caminho do arquivo de log Critico
CRITICALLOG_DIR='/var/log/redundance/redundanceErr'
# Caminho do arquivo de log Critico
CRITICALLOG=$CRITICALLOG_DIR'/redundanceErr.log'
# Caminho do diretorio para o log
LOGDIR='/var/log/redundance'
# Caminho do arquivo de LOG
LOG=$LOGDIR'/redundance.log'
# Criando o diretorio/arquivo de log caso nao exista 
if [ ! -d "$LOGDIR" ]; then
	sudo mkdir $LOGDIR ; touch $LOG
fi
# Criando o diretorio/arquivo de logCritical caso nao exista
if [ ! -d "$CRITICALLOG_DIR" ]; then
        sudo mkdir $CRITICALLOG_DIR ; touch $CRITICALLOG 
fi
# Permissao para arquivo de log
sudo chmod 777 $LOG && sudo chmod 777 $CRITICALLOG

# Placa primaria
IF1=eth0:2 ; export IF1
# Placa secundaria
IF2=eth0:3 ; export IF2

IPtest1=8.8.8.8 ; export IPtest1
IPtest2=8.8.4.4 ; export IPtest2

# Descobrindo qual eh o gateway default ativo e setando em uma variavel o IP dele
GW_DEFAULT_UP(){
	echo "`ip route show | egrep -e "^default*" | awk '{print $3}'`"
} 

# Comando customizado para ser executado após a alteração do gateway
# obs: alguns lugares tem necessidade de efetuar alguma configuracao apos mudar a internet
# exemplo : restartar o squid após mudar o gateway
COMMAND_CUSTOM(){
	# Inserir abaixo o comando necessario
	# ex: sudo service squid3 restart
}

# Gateway principal 
#GW1= ; export GW1 #aqui entro com meu gateway prioritario

# Gateway secundario
#GW2= ; export GW2 #aqui entro com meu gateway de backup

#############################################################################################
## Em caso de uso de multiplos gateways (mais de 2) será necessario setar todos aqui antes ##
## e tambem comentar o (GW1 e GW2) que esta acima                                          ##
## Usaremos um array chamado LINKS e setar os ips dos gateways conforme seu peso           ##
## -- mutiples gateways. Ex:
declare -A LINKS
LINKS[01]="0.0.0.0"
LINKS[02]="0.0.0.1"
LINKS[03]="0.0.0.2"
LINKS[04]="0.0.0.3"
#############################################################################################

#
# Funcao para escrever em arquivo de log
#
writeLog(){
	echo "[`date`] - $1 " >> $LOG
}

#
# Funcao para escrever em arquivo de log Critico
#
writeCritical(){
	echo "[`date`] - $1 " >> $CRITICALLOG
}

#
# Funcao para fazer teste no gateway padrao
#
testGw(){
	# Fazendo ping pela placa de rede passada para testar
	ping 8.8.8.8 -c 5 -A > /dev/null
	if [ $? -eq 0 ] ; then
		return 0 # retornado true
	else
		return 1 # retornando false
	fi
}

#
# Funcao para checar se o parametro passado eh o gateway default
#
checkDefault(){
	if [ $1 == `GW_DEFAULT_UP` ] ; then
		return 0 # retornando true
	else
		return 1 # retornando false
	fi
}



#
# Funcao para fazer teste em um determinado gateway de uma placa especifica
# essa funcao adiciona um ip para sair por um determinado gateway e depois pinga esse ip
#
testEspecificGw(){
	route add $1 gw $2 > /dev/null
	ping $1 -c 5 -A > /dev/null
	if [ $? -eq 0 ] ; then
		route del $1 gw $2 > /dev/null && return 0 # Sempre removemos a rota criada e retornamos positivo/negativo
	else
		route del $1 gw $2 > /dev/null && return 1 # Sempre removemos a rota criada e retornamos positivo/negativo
	fi
}

#
# Funcao para testar os links e ver se o gateway primario voltou
#
testPrimaryGw(){
	while :; do
		# verificando se o gateway default eh o mesmo que o gateway primario (GW1)
		if [ `GW_DEFAULT_UP` == $GW1 ]; then 
			# ja que o GW default eh o mesmo que o GW1 entao testamos o default (teste de ping)
			if testEspecificGw $IPtest1 $GW1; then 
				writeLog "Gateway $GW1 (placa $IF1) esta respondendo a internet e eh Default"
				sleep 1
			else # Else da condicao de funcionamento do gw1
				# alterando o GW default para o gateway secundario pois nao passou no teste de ping
				writeLog "Gateway $GW1 (placa $IF1) nao esta respondendo a internet e eh Default"
				writeCritical "Gateway $GW1 (placa $IF1) nao esta respondendo a internet e eh Default"
				if changeGw $GW2 $GW1; then # o primeiro parametro indica o gateway a ser trocado, o segundo eh removido
					writeLog "O gateway $GW2 foi definido como padrao"
				fi
			fi
		else # Else da condicao de o GW1 nao ser o gateway Default
			# testando agora com o gateway alterado
			if testEspecificGw $IPtest1 $GW1; then 
				# gateway 1 esta funcionando
				writeLog "Gateway $GW1 (placa $IF1) esta respondendo a internet e nao eh Default "
				if changeGw $GW1 $GW2; then
					writeLog "O gateway $GW1 foi definido como padrao pois voltou a operar"
				fi
			else # Else da condicao de o GW1 ter voltado a operar
				# retomando para o gateway secundario pois o primeiro nao voltou a funcionar
				writeLog "Gateway $GW1 (placa $IF1) nao esta respondendo a internet e nao eh default 1 (nao voltou a operar)"
				writeCritical "Gateway $GW1 (placa $IF1) nao esta respondendo a internet e nao eh Default (nao voltou a operar)"
			fi
		fi
	done
}

#
# Funcao para testar apenas uma placa e alterar o gateway para o contrário assim que parar de responder
# obs: essa funcao nao altera o gateway para ver se o primario voltou a funcionar
#
testOnlyIf(){
	while :; do
		# Verificando se o gateway atual esta respondendo a internet
		if testGw; then
			writeLog "Gateway default (`GW_DEFAULT_UP`) esta respondendo a internet"
			sleep 2
		# alterando o gateway caso estiver falhando
		elif [ `GW_DEFAULT_UP` == $GW1 ]; then # verifico qual Gateway eh o atual para mudar ao secundario
			writeLog "O gateway `GW_DEFAULT_UP` parou de responder a internet !"
			writeCritical "O gateway `GW_DEFAULT_UP` parou de responder a internet !"
			changeGw $GW2 $GW1 # altero para o secundario pois o primario eh o default e nao responde
		else
			writeLog "O gateway `GW_DEFAULT_UP` parou de responder a internet !"
			writeCritical "O gateway `GW_DEFAULT_UP` parou de responder a internet !"
			changeGw $GW1 $GW2 # altero para o primario pois o secundario eh o default e nao responde
		fi
	done
}

#
# Funcao para testar varios links com prioridades definidas por um array
# obs: eh necessario criar as variaveis no inicio do script para cada gateway, seguindo o padrao 'GW+PRIORIDADE_EM_NUMERO'
# ex : GW1, GW2, GW3 etc etc
#
testMultipleGw(){
	# Fazendo loop para ficar vendo a conexao com a internet
	while :; do
		if testGw ; then # condicao para saber se a internet esta operando
			minimalOpGw=`minimalGateway` # Setando o gateway de menor peso e funcional
			# sob a condicao de ter internet, agora veririco se o gateway atual (default) eh o de menor peso
			if [ `GW_DEFAULT_UP` == $minimalOpGw ] ; then
				writeLog "O gateway ($minimalOpGw) está operante e é o gateway de menor peso (maior prioridade)"
			else
				# O gateway atual nao eh o de menor peso, entao adicionamos o menor e removemos o atual
				changeGw $minimalOpGw `GW_DEFAULT_UP`  
				writeLog "O gateway atual foi alterado para o de menor peso que está respondendo a internet ($minimalOpGw)"
			fi
		else # Else para caso nao tenha internet
			writeLog "O gateway padrao nao tem conexao (`GW_DEFAULT_UP`) será alterado"
			minimalOpGw=`minimalGateway`
			changeGw $minimalOpGw `GW_DEFAULT_UP`
			writeLog "Alterado para o menor gateway pois a internet está down ($minimalOpGw)"
		fi
	done	
}


#
# Funcao para testar o gateway de menor prioridade e retornar ele
#
minimalGateway(){
	for gw in ${LINKS[@]} ; do
		# Testando o ip do LOOP para ver qual responde mais rapido
		if testEspecificGw $IPtest1 $gw ; then 
			echo $gw && exit 
		else
			let cont=$cont+1 ; export cont
		fi
		# Verificando se todos os gateways estao down
		if [ $cont -eq ${#LINKS[@]} ] ; then
			writeLog "Todos os gateways estao down" && echo "`GW_DEFAULT_UP`" && exit
		fi
	done | sort  
}

#
# Funcao para alterar os gateways, o primeiro parametro passado sera adicionado e o segundo removido
#
changeGw(){
	# adicionando o gateway padrao para outro passado
	sudo route add default gw $1
	writeLog "Gateway $1 adicionado"
	writeCritical "Gateway $1 adicionado"
	# removendo o gateway que estava anteriormente 
	sudo route del default gw $2	
	writeLog "Gateway $2 removido"
	writeCritical "gateway $2 removido"
	# vendo quem eh o gateway atual depois da mudanca pelo route add/del	
	GW_ATUAL=`GW_DEFAULT_UP`
	# testando se o gateway foi alterado e retornando positivo caso sim
	if [ $GW_ATUAL == $1 ]; then
		return 0 && `COMMAND_CUSTOM` # Alguns lugares precisam de certos ajustes após mudar o gateway
	else				     # por isso criei uma funcao que pode ser preenchida com qualquer comando					
		return 1 && `COMMAND_CUSTOM` # para ser feito apos a mudanca do gateway
	fi
}

testMultipleGw
