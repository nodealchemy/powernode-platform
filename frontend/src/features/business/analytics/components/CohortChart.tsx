import { format, parseISO } from 'date-fns';

interface CohortChartProps {
  data: Array<{
    cohort_date: string;
    cohort_size: number;
    retention_rates: Array<{
      month: number;
      retention_rate: number;
      retained_customers: number;
    }>;
  }>;
  summary?: {
    total_cohorts: number;
    average_first_month_retention: number;
    average_six_month_retention: number;
  };
  title: string;
}

export const CohortChart: React.FC<CohortChartProps> = ({
  data,
  summary,
  title
}) => {
  const formatDate = (dateString: string) => {
    try {
      return format(parseISO(dateString + '-01'), 'MMM yyyy');
    } catch (_error) {
      return dateString;
    }
  };

  const formatPercentage = (value: number) => {
    return `${Math.round(value)}%`;
  };

  const getRetentionColor = (rate: number) => {
    if (rate >= 80) return `bg-theme-success text-white`;
    if (rate >= 60) return `bg-theme-info text-white`;
    if (rate >= 40) return `bg-theme-warning text-white`;
    if (rate >= 20) return `bg-theme-warning text-white`;
    if (rate > 0) return `bg-theme-error text-white`;
    return 'bg-theme-background-secondary text-theme-secondary';
  };

  // Prepare data for the cohort table - handle empty data
  const maxMonths = data.length > 0 ? Math.max(...data.map(cohort => cohort.retention_rates.length)) : 0;
  const months = Array.from({ length: maxMonths }, (_, i) => i);

  // Handle empty data state
  if (!data || data.length === 0) {
    return (
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">{title}</h3>
        <div className="text-center py-12">
          <div className="w-16 h-16 mx-auto mb-4 bg-theme-background-secondary rounded-full flex items-center justify-center">
            <svg className="w-8 h-8 text-theme-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
            </svg>
          </div>
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Cohort Data Available</h3>
          <p className="text-theme-secondary">
            Cohort analysis will appear here once you have customers with sufficient historical data.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Summary Metrics */}
      {summary && (
        <div className="card-theme rounded-lg shadow-sm border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Cohort Summary</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <p className="text-sm text-theme-secondary">Total Cohorts</p>
              <p className="text-2xl font-bold text-theme-info">{summary.total_cohorts}</p>
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Avg 1st Month Retention</p>
              <p className="text-2xl font-bold text-theme-success">
                {formatPercentage(summary.average_first_month_retention)}
              </p>
            </div>
            <div>
              <p className="text-sm text-theme-secondary">Avg 6th Month Retention</p>
              <p className="text-2xl font-bold text-theme-primary">
                {formatPercentage(summary.average_six_month_retention)}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Cohort Retention Heatmap */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Cohort Retention Analysis</h3>
        
        {/* Legend */}
        <div className="flex flex-wrap items-center justify-center gap-3 mb-6 text-sm">
          <span className="text-theme-secondary font-medium">Retention Rate:</span>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-theme-error rounded shadow-sm"></div>
            <span className="text-theme-secondary">0-20%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-theme-warning rounded shadow-sm"></div>
            <span className="text-theme-secondary">20-40%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-theme-warning rounded shadow-sm"></div>
            <span className="text-theme-secondary">40-60%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-theme-info rounded shadow-sm"></div>
            <span className="text-theme-secondary">60-80%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-theme-success rounded shadow-sm"></div>
            <span className="text-theme-secondary">80%+</span>
          </div>
        </div>

        {/* Cohort Table */}
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-theme">
                <th className="px-4 py-3 text-left text-xs font-semibold text-theme-secondary uppercase tracking-wider">
                  Cohort
                </th>
                <th className="px-4 py-3 text-left text-xs font-semibold text-theme-secondary uppercase tracking-wider">
                  Size
                </th>
                {months.map(month => (
                  <th key={month} className="px-3 py-3 text-center text-xs font-semibold text-theme-secondary uppercase tracking-wider">
                    M{month}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="card-theme divide-y divide-theme">
              {data.map((cohort, cohortIndex) => (
                <tr key={cohortIndex} className={cohortIndex % 2 === 0 ? 'bg-theme-background-secondary' : 'card-theme'}>
                  <td className="px-4 py-4 whitespace-nowrap text-sm font-medium text-theme-primary">
                    {formatDate(cohort.cohort_date)}
                  </td>
                  <td className="px-4 py-4 whitespace-nowrap text-sm text-theme-secondary">
                    {cohort.cohort_size.toLocaleString()}
                  </td>
                  {months.map(monthIndex => {
                    const retentionData = cohort.retention_rates.find(r => r.month === monthIndex);
                    if (!retentionData) {
                      return (
                        <td key={monthIndex} className="px-3 py-4 text-center">
                          <div className="w-full h-8 bg-theme-background-tertiary rounded flex items-center justify-center">
                            <span className="text-xs text-theme-tertiary">-</span>
                          </div>
                        </td>
                      );
                    }

                    const rate = retentionData.retention_rate * 100;
                    return (
                      <td key={monthIndex} className="px-3 py-4 text-center">
                        <div 
                          className={`w-full h-8 rounded flex items-center justify-center cursor-pointer ${getRetentionColor(rate)}`}
                          title={`${formatPercentage(rate)} (${retentionData.retained_customers} customers)`}
                        >
                          <span className="text-xs font-medium">
                            {formatPercentage(rate)}
                          </span>
                        </div>
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Retention Curves */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Retention Curves</h3>
        <div className="h-96">
          <svg viewBox="0 0 800 400" className="w-full h-full">
            <defs>
              {data.map((_, index) => (
                <linearGradient key={index} id={`gradient-${index}`} x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" style={{ stopColor: `hsl(${index * 360 / data.length}, 70%, 50%)`, stopOpacity: 0.8 }} />
                  <stop offset="100%" style={{ stopColor: `hsl(${index * 360 / data.length}, 70%, 50%)`, stopOpacity: 0.3 }} />
                </linearGradient>
              ))}
            </defs>
            
            {/* Grid lines */}
            {[0, 20, 40, 60, 80, 100].map(y => (
              <line
                key={y}
                x1="50"
                y1={350 - (y * 3)}
                x2="750"
                y2={350 - (y * 3)}
                stroke="rgba(0, 0, 0, 0.06)"
                strokeWidth="1"
              />
            ))}
            
            {/* Y-axis labels */}
            {[0, 20, 40, 60, 80, 100].map(y => (
              <text
                key={y}
                x="35"
                y={355 - (y * 3)}
                textAnchor="end"
                fontSize="12"
                fill="#6b7280"
              >
                {y}%
              </text>
            ))}
            
            {/* X-axis labels */}
            {months.slice(0, 13).map(month => (
              <text
                key={month}
                x={50 + (month * 50)}
                y="375"
                textAnchor="middle"
                fontSize="12"
                fill="#6b7280"
              >
                M{month}
              </text>
            ))}
            
            {/* Retention curves */}
            {data.map((cohort, cohortIndex) => {
              const points = cohort.retention_rates
                .slice(0, 13)
                .map(r => ({
                  x: 50 + (r.month * 50),
                  y: 350 - (r.retention_rate * 100 * 3)
                }));
              
              const pathData = points.length > 0 ? points.reduce((path, point, index) => {
                return path + (index === 0 ? `M ${point.x} ${point.y}` : ` L ${point.x} ${point.y}`);
              }, '') : '';
              
              return (
                <g key={cohortIndex}>
                  <path
                    d={pathData}
                    fill="none"
                    stroke={`hsl(${cohortIndex * 360 / data.length}, 70%, 50%)`}
                    strokeWidth="2"
                    opacity="0.8"
                  />
                  {points.map((point, pointIndex) => (
                    <circle
                      key={pointIndex}
                      cx={point.x}
                      cy={point.y}
                      r="3"
                      fill={`hsl(${cohortIndex * 360 / data.length}, 70%, 50%)`}
                    >
                      <title>
                        {(() => {
                          const retentionData = cohort.retention_rates.find((_r, idx) => idx === pointIndex);
                          return retentionData ?
                            `${formatDate(cohort.cohort_date)} - Month ${retentionData.month}: ${formatPercentage(retentionData.retention_rate * 100)}` :
                            formatDate(cohort.cohort_date);
                        })()}
                      </title>
                    </circle>
                  ))}
                </g>
              );
            })}
          </svg>
        </div>
        
        {/* Legend */}
        <div className="mt-4 grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3">
          {data.slice(0, 12).map((cohort, index) => (
            <div key={index} className="flex items-center space-x-2 text-sm p-2 bg-theme-background-secondary rounded">
              <div
                className="w-3 h-3 rounded-full flex-shrink-0 shadow-sm"
                style={{ backgroundColor: `hsl(${index * 360 / data.length}, 70%, 50%)` }}
              ></div>
              <span className="text-theme-secondary truncate font-medium">
                {formatDate(cohort.cohort_date)}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Cohort Performance Insights */}
      <div className="card-theme rounded-lg shadow-sm border-theme p-6">
        <h3 className="text-lg font-semibold text-theme-primary mb-4">Cohort Performance Insights</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {/* Best Performing Cohort */}
          {data.length > 0 && (() => {
            const bestCohort = data.reduce((best, cohort) => {
              const sixMonthRetention = cohort.retention_rates.find(r => r.month === 6);
              const bestSixMonth = best.retention_rates.find(r => r.month === 6);
              
              if (!sixMonthRetention) return best;
              if (!bestSixMonth) return cohort;
              
              return sixMonthRetention.retention_rate > bestSixMonth.retention_rate ? cohort : best;
            });
            
            const sixMonthRetention = bestCohort.retention_rates.find(r => r.month === 6);
            
            return (
              <div className="p-4 bg-theme-success-light border border-theme-success rounded-lg">
                <h4 className="font-medium text-theme-success mb-2">🏆 Best Performing Cohort</h4>
                <p className="text-sm text-theme-success">
                  {formatDate(bestCohort.cohort_date)} with{' '}
                  {sixMonthRetention ? formatPercentage(sixMonthRetention.retention_rate * 100) : 'N/A'} 
                  {' '}6-month retention
                </p>
                <p className="text-xs text-theme-success mt-1">
                  Cohort size: {bestCohort.cohort_size.toLocaleString()}
                </p>
              </div>
            );
          })()}

          {/* Largest Cohort */}
          {data.length > 0 && (() => {
            const largestCohort = data.reduce((largest, cohort) => 
              cohort.cohort_size > largest.cohort_size ? cohort : largest
            );
            
            return (
              <div className="p-4 bg-theme-info-light border border-theme-info rounded-lg">
                <h4 className="font-medium text-theme-info mb-2">📈 Largest Cohort</h4>
                <p className="text-sm text-theme-info">
                  {formatDate(largestCohort.cohort_date)} with{' '}
                  {largestCohort.cohort_size.toLocaleString()} customers
                </p>
                {(() => {
                  const sixMonthRetention = largestCohort.retention_rates.find(r => r.month === 6);
                  return sixMonthRetention ? (
                    <p className="text-xs text-theme-info mt-1">
                      6-month retention: {formatPercentage(sixMonthRetention.retention_rate * 100)}
                    </p>
                  ) : null;
                })()}
              </div>
            );
          })()}

          {/* Average Retention Trend */}
          <div className="p-4 bg-theme-primary-light border border-theme-primary rounded-lg">
            <h4 className="font-medium text-theme-primary mb-2">📊 Retention Trend</h4>
            <p className="text-sm text-theme-primary">
              {data.length > 1 && (() => {
                const firstCohort = data[data.length - 1];
                const lastCohort = data[0];
                const firstRetention = firstCohort.retention_rates.find(r => r.month === 3);
                const lastRetention = lastCohort.retention_rates.find(r => r.month === 3);
                
                if (!firstRetention || !lastRetention) return 'Insufficient data';
                
                const trend = lastRetention.retention_rate - firstRetention.retention_rate;
                return trend > 0 
                  ? `📈 Improving by ${formatPercentage(Math.abs(trend) * 100)}`
                  : trend < 0
                  ? `📉 Declining by ${formatPercentage(Math.abs(trend) * 100)}`
                  : '➡️ Stable retention';
              })()}
            </p>
            <p className="text-xs text-theme-primary mt-1">
              3-month retention comparison
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};