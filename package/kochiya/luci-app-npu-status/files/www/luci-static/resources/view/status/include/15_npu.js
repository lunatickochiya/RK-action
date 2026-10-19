'use strict';
'require baseclass';
'require rpc';

var callStatus = rpc.declare({
	object: 'npu_status',
	method: 'status',
	expect: {}
});

function bar(pct, label) {
	pct = Math.max(0, Math.min(100, +pct || 0));
	return E('div', { 'style': 'display:flex;align-items:center;margin:2px 0' }, [
		E('span', { 'style': 'width:64px;flex:none' }, [ label ]),
		E('div', { 'class': 'cbi-progressbar', 'style': 'flex:1', 'title': pct + '%' },
			E('div', { 'style': 'width:' + pct + '%' }, [])),
		E('span', { 'style': 'width:44px;text-align:right' }, [ pct + '%' ])
	]);
}

function mhz(v) {
	v = +v || 0;
	return v ? (v / 1000000).toFixed(0) + ' MHz' : '—';
}

function temp(v) {
	v = +v || 0;
	return v ? (v / 1000).toFixed(1) + ' °C' : '—';
}

return baseclass.extend({
	title: 'NPU / VPU',

	load: function() {
		return L.resolveDefault(callStatus(), {});
	},

	render: function(d) {
		var sessions = ((d.vpu_sessions || '').match(/session:/g) || []).length;

		var rows = [
			[ 'NPU 负载', E('div', {}, [
				bar(d.core0, 'Core 0'),
				bar(d.core1, 'Core 1'),
				bar(d.core2, 'Core 2') ]) ],
			[ 'NPU 驱动', (d.npu_ver || '—') + ' · ' + mhz(d.npu_freq) ],
			[ 'VPU 解码', 'Core0 ' + mhz(d.dec0_clk) + ' · ' + (d.dec0_tasks || 0) + ' 任务　Core1 ' + mhz(d.dec1_clk) + ' · ' + (d.dec1_tasks || 0) + ' 任务' ],
			[ 'VPU 编码', 'Core0 ' + mhz(d.enc0_clk) + ' · ' + (d.enc0_tasks || 0) + ' 会话　Core1 ' + mhz(d.enc1_clk) + ' · ' + (d.enc1_tasks || 0) + ' 会话' ],
			[ 'VPU 活动会话', String(sessions) ],
			[ '温度', 'SoC ' + temp(d.temp_package) + ' · NPU ' + temp(d.temp_npu) + ' · GPU ' + temp(d.temp_gpu) ],
			[ 'Load', d.loadavg || '—' ]
		];

		var table = E('table', { 'class': 'table' });
		for (var i = 0; i < rows.length; i++) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ rows[i][0] ]),
				E('td', { 'class': 'td left' }, [ rows[i][1] != null ? rows[i][1] : '?' ])
			]));
		}
		return table;
	}
});
