using DimDim.Web.Models;
using Microsoft.EntityFrameworkCore;

namespace DimDim.Web.Data;

public class DimDimContext(DbContextOptions<DimDimContext> options) : DbContext(options)
{
    public DbSet<Conta> Contas => Set<Conta>();
    public DbSet<Transacao> Transacoes => Set<Transacao>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Conta>(entity =>
        {
            entity.ToTable("conta", t => t.HasCheckConstraint("CK_conta_saldo_inicial", "saldo_inicial BETWEEN -9999999999999999 AND 9999999999999999"));
            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.Nome).HasColumnName("nome");
            entity.Property(x => x.Instituicao).HasColumnName("instituicao");
            entity.Property(x => x.Tipo).HasColumnName("tipo");
            entity.Property(x => x.SaldoInicial).HasColumnName("saldo_inicial");
            entity.HasIndex(x => x.Nome);
        });

        modelBuilder.Entity<Transacao>(entity =>
        {
            entity.ToTable("transacao", t => t.HasCheckConstraint("CK_transacao_valor", "valor > 0"));
            entity.Property(x => x.Id).HasColumnName("id");
            entity.Property(x => x.Descricao).HasColumnName("descricao");
            entity.Property(x => x.Valor).HasColumnName("valor");
            entity.Property(x => x.Data).HasColumnName("data").HasColumnType("date");
            entity.Property(x => x.Tipo).HasColumnName("tipo").HasConversion<string>().HasMaxLength(10);
            entity.Property(x => x.ContaId).HasColumnName("conta_id");
            entity.HasIndex(x => new { x.ContaId, x.Data });
            entity.HasOne(x => x.Conta).WithMany(x => x.Transacoes).HasForeignKey(x => x.ContaId).OnDelete(DeleteBehavior.Restrict);
        });
    }
}
